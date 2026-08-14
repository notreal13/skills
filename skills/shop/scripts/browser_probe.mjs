#!/usr/bin/env node

import { spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const DEFAULT_CHROME_PATHS = [
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  "/Applications/Chromium.app/Contents/MacOS/Chromium",
  "/usr/bin/google-chrome",
  "/usr/bin/chromium",
  "/usr/bin/chromium-browser",
];

function usage(message) {
  if (message) console.error(message);
  console.error(`Usage: browser_probe.mjs --url URL [options]

Options:
  --click TEXT          Click visible text; repeat to select nested variants
  --wait-ms NUMBER      Wait after load and after each click (default: 2500)
  --timeout-ms NUMBER   Startup/navigation timeout (default: 45000)
  --text-limit NUMBER   Maximum visible-text characters returned (default: 50000)
  --controls            Include inspectable controls and variant attributes
  --screenshot PATH     Save a final PNG only when explicitly requested
  --headed              Show the isolated Chrome window instead of headless mode
  --chrome-path PATH    Override Chrome executable (or set SHOP_CHROME_PATH)
`);
  process.exit(message ? 2 : 0);
}

function parseArgs(argv) {
  const options = {
    clicks: [],
    waitMs: 2500,
    timeoutMs: 45000,
    textLimit: 50000,
    headed: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    const value = () => {
      index += 1;
      if (index >= argv.length) usage(`Missing value for ${argument}`);
      return argv[index];
    };

    if (argument === "--url") options.url = value();
    else if (argument === "--click") options.clicks.push(value());
    else if (argument === "--wait-ms") options.waitMs = Number(value());
    else if (argument === "--timeout-ms") options.timeoutMs = Number(value());
    else if (argument === "--text-limit") options.textLimit = Number(value());
    else if (argument === "--controls") options.controls = true;
    else if (argument === "--screenshot") options.screenshot = value();
    else if (argument === "--chrome-path") options.chromePath = value();
    else if (argument === "--headed") options.headed = true;
    else if (argument === "--help" || argument === "-h") usage();
    else if (!argument.startsWith("-") && !options.url) options.url = argument;
    else usage(`Unknown argument: ${argument}`);
  }

  if (!options.url) usage("--url is required");
  let parsedUrl;
  try {
    parsedUrl = new URL(options.url);
  } catch {
    usage("--url must be an absolute URL");
  }
  if (!["http:", "https:", "file:"].includes(parsedUrl.protocol)) {
    usage("Only http, https, and file URLs are allowed");
  }
  for (const key of ["waitMs", "timeoutMs", "textLimit"]) {
    if (!Number.isFinite(options[key]) || options[key] < 0) {
      usage(`Invalid numeric value for ${key}`);
    }
  }
  return options;
}

function findChrome(explicitPath) {
  const candidates = [explicitPath, process.env.SHOP_CHROME_PATH, ...DEFAULT_CHROME_PATHS]
    .filter(Boolean);
  const chromePath = candidates.find((candidate) => fs.existsSync(candidate));
  if (!chromePath) {
    throw new Error("Chrome/Chromium not found; use --chrome-path or SHOP_CHROME_PATH");
  }
  return chromePath;
}

const sleep = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

async function waitForFile(filePath, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (fs.existsSync(filePath)) return;
    await sleep(100);
  }
  throw new Error(`Chrome did not create ${path.basename(filePath)} within ${timeoutMs} ms`);
}

class CdpClient {
  constructor(socket) {
    this.socket = socket;
    this.nextId = 1;
    this.pending = new Map();
    socket.addEventListener("message", (event) => this.handleMessage(event));
  }

  static async connect(socketUrl, timeoutMs) {
    const socket = new WebSocket(socketUrl);
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("CDP WebSocket connection timed out")), timeoutMs);
      socket.addEventListener("open", () => {
        clearTimeout(timer);
        resolve();
      }, { once: true });
      socket.addEventListener("error", () => {
        clearTimeout(timer);
        reject(new Error("Could not connect to Chrome DevTools Protocol"));
      }, { once: true });
    });
    return new CdpClient(socket);
  }

  handleMessage(event) {
    const message = JSON.parse(event.data);
    if (message.id) {
      const pending = this.pending.get(message.id);
      if (!pending) return;
      this.pending.delete(message.id);
      if (message.error) pending.reject(new Error(message.error.message));
      else pending.resolve(message.result);
      return;
    }
  }

  send(method, params = {}) {
    const id = this.nextId;
    this.nextId += 1;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  close() {
    this.socket.close();
  }
}

async function evaluate(client, expression) {
  const result = await client.send("Runtime.evaluate", {
    expression,
    awaitPromise: true,
    returnByValue: true,
    userGesture: true,
  });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.exception?.description || "Browser evaluation failed");
  }
  return result.result.value;
}

async function waitForDocument(client, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  let lastState;
  while (Date.now() < deadline) {
    lastState = await evaluate(client, `(() => ({
      url: location.href,
      readyState: document.readyState,
      title: document.title,
      textLength: document.body?.innerText?.length || 0
    }))()`);
    if (
      lastState.url !== "about:blank"
      && lastState.readyState !== "loading"
      && (lastState.title || lastState.textLength > 0)
    ) return lastState;
    await sleep(200);
  }
  throw new Error(`Navigation did not produce a readable document: ${JSON.stringify(lastState)}`);
}

function clickExpression(requestedText) {
  return `(() => {
    const requested = ${JSON.stringify(requestedText)};
    const normalize = (value) => (value || "").replace(/\\s+/g, " ").trim().toLocaleLowerCase("ru");
    const wanted = normalize(requested);
    const visible = (element) => {
      const style = getComputedStyle(element);
      const box = element.getBoundingClientRect();
      return style.visibility !== "hidden" && style.display !== "none" && box.width > 0 && box.height > 0;
    };
    const textOf = (element) => element.getAttribute("aria-label") || element.getAttribute("title") || element.getAttribute("data-title") || element.getAttribute("data-value") || element.getAttribute("data-wvstooltip") || element.getAttribute("alt") || element.innerText || element.textContent || element.value || "";
    const elements = [...document.querySelectorAll("button, a, [role=button], [role=option], label, option, input, [tabindex], [title], [data-title], [data-value], [data-wvstooltip], li, div, span")]
      .filter(visible)
      .map((element) => ({ element, text: textOf(element), normalized: normalize(textOf(element)) }))
      .filter((candidate) => candidate.normalized === wanted || candidate.normalized.includes(wanted))
      .sort((left, right) => Number(right.normalized === wanted) - Number(left.normalized === wanted) || left.text.length - right.text.length);
    const match = elements[0];
    if (!match) return { found: false, requested };
    const element = match.element;
    element.scrollIntoView({ block: "center", inline: "center" });
    if (element.tagName === "OPTION" && element.parentElement?.tagName === "SELECT") {
      element.parentElement.value = element.value;
      element.parentElement.dispatchEvent(new Event("input", { bubbles: true }));
      element.parentElement.dispatchEvent(new Event("change", { bubbles: true }));
    } else {
      element.click();
    }
    return {
      found: true,
      requested,
      matched: match.text.replace(/\\s+/g, " ").trim().slice(0, 300),
      exact: match.normalized === wanted,
      tag: element.tagName.toLowerCase(),
    };
  })()`;
}

async function stopChrome(child) {
  if (child.exitCode !== null) return;
  child.kill("SIGTERM");
  await Promise.race([
    new Promise((resolve) => child.once("exit", resolve)),
    sleep(2000),
  ]);
  if (child.exitCode === null) child.kill("SIGKILL");
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  const chromePath = findChrome(options.chromePath);
  const profileDir = fs.mkdtempSync(path.join(os.tmpdir(), "shop-chrome-"));
  const devtoolsFile = path.join(profileDir, "DevToolsActivePort");
  const chromeErrors = [];
  let child;
  let client;

  try {
    const chromeArgs = [
      `--user-data-dir=${profileDir}`,
      "--remote-debugging-port=0",
      "--no-first-run",
      "--no-default-browser-check",
      "--disable-background-networking",
      "--disable-component-update",
      "--disable-sync",
      "--disable-breakpad",
      "--metrics-recording-only",
      "--no-report-upload",
      "--lang=ru-RU",
      "--window-size=1440,1200",
      ...(options.headed ? [] : ["--headless=new"]),
      "about:blank",
    ];
    child = spawn(chromePath, chromeArgs, { stdio: ["ignore", "ignore", "pipe"] });
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk) => {
      chromeErrors.push(chunk);
      if (chromeErrors.length > 20) chromeErrors.shift();
    });

    await waitForFile(devtoolsFile, options.timeoutMs);
    const [port] = fs.readFileSync(devtoolsFile, "utf8").trim().split(/\r?\n/);
    const targetResponse = await fetch(`http://127.0.0.1:${port}/json/new?about:blank`, { method: "PUT" });
    if (!targetResponse.ok) throw new Error(`Could not create Chrome target: HTTP ${targetResponse.status}`);
    const target = await targetResponse.json();
    client = await CdpClient.connect(target.webSocketDebuggerUrl, options.timeoutMs);
    await client.send("Page.enable");
    await client.send("Runtime.enable");

    const navigation = await client.send("Page.navigate", { url: options.url });
    if (navigation.errorText) throw new Error(`Navigation failed: ${navigation.errorText}`);
    await waitForDocument(client, options.timeoutMs);
    await sleep(options.waitMs);

    const actions = [];
    for (const requestedText of options.clicks) {
      const action = await evaluate(client, clickExpression(requestedText));
      actions.push(action);
      if (!action.found) break;
      await sleep(options.waitMs);
    }

    const page = await evaluate(client, `(() => {
      const interestingAttributes = ["id", "class", "name", "type", "value", "title", "aria-label", "data-title", "data-value", "data-wvstooltip", "data-attribute_name"];
      const controls = ${options.controls ? `[...document.querySelectorAll("button, input, select, option, [role=button], [role=option], [aria-label], [title], [data-title], [data-value], [data-wvstooltip]")]
        .slice(0, 300)
        .map((element) => ({
          tag: element.tagName.toLowerCase(),
          text: (element.innerText || element.textContent || "").replace(/\\s+/g, " ").trim().slice(0, 160),
          attributes: Object.fromEntries(interestingAttributes.flatMap((name) => {
            const sensitiveInputValue = name === "value" && element.tagName === "INPUT" && ["hidden", "password"].includes(element.type);
            return element.hasAttribute(name) && !sensitiveInputValue ? [[name, element.getAttribute(name).slice(0, 300)]] : [];
          })),
        }))` : "[]"};
      const selectedControls = [...document.querySelectorAll("select, input:checked, [aria-selected=true], .wd-swatch.wd-active, .selected.active")]
        .map((element) => ({
          tag: element.tagName.toLowerCase(),
          text: (element.selectedOptions?.[0]?.textContent || element.innerText || element.textContent || "").replace(/\\s+/g, " ").trim().slice(0, 160),
          name: element.getAttribute("name") || null,
          value: element.value || element.getAttribute("data-value") || null,
        }))
        .filter((control) => control.text || control.value);
      return {
        title: document.title,
        url: location.href,
        text: (document.body?.innerText || "").slice(0, ${options.textLimit}),
        controls,
        selectedControls,
      };
    })()`);
    const normalizedText = page.text.replace(/\u00a0/g, " ");
    const priceMatches = normalizedText.match(/(?:\d[\d ]{2,}\s*(?:₽|руб(?:\.|лей)?))|(?:(?:₽|руб\.)\s*\d[\d ]{2,})/giu) || [];
    const prices = [...new Set(priceMatches.map((price) => price.replace(/\s+/g, " ").trim()))].slice(0, 50);
    const challenge = /captcha|verify you are human|подтвердите.{0,30}(?:человек|не робот)|проверка.{0,20}браузер/iu.test(normalizedText);
    const blocked = /^(?:http\s*)?(?:401|403|429)\b/iu.test(page.title.trim())
      || /\b(?:401|403|429)\s+(?:error|forbidden|unauthorized|too many requests)\b|access.{0,40}(?:forbidden|denied)|доступ.{0,30}(?:ограничен|заблокирован|запрещён)/iu.test(normalizedText);

    if (options.screenshot) {
      const screenshot = await client.send("Page.captureScreenshot", { format: "png", captureBeyondViewport: false });
      fs.writeFileSync(path.resolve(options.screenshot), Buffer.from(screenshot.data, "base64"));
    }

    const output = {
      ok: actions.every((action) => action.found) && !challenge && !blocked,
      browser: "local-chrome-cdp",
      mode: options.headed ? "headed" : "headless",
      isolatedProfile: true,
      title: page.title,
      url: page.url,
      actions,
      challenge,
      blocked,
      prices,
      selectedControls: page.selectedControls,
      visibleText: page.text,
    };
    if (options.controls) output.controls = page.controls;
    console.log(JSON.stringify(output, null, 2));
    process.exitCode = output.ok ? 0 : 3;
  } catch (error) {
    const stderrTail = chromeErrors.join("").trim().split(/\r?\n/).slice(-8).join("\n");
    console.error(JSON.stringify({
      ok: false,
      browser: "local-chrome-cdp",
      error: error.message,
      chromeStderrTail: stderrTail,
    }, null, 2));
    process.exitCode = 1;
  } finally {
    if (client) client.close();
    if (child) await stopChrome(child);
    fs.rmSync(profileDir, { recursive: true, force: true });
  }
}

await main();
