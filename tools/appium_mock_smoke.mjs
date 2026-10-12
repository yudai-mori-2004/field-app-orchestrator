const requiredEnvironment = ["FAO_DEVICE_ID", "FAO_DEVELOPMENT_TEAM"];
for (const name of requiredEnvironment) {
  if (!process.env[name]) {
    throw new Error(`${name} is required and must be provided at runtime.`);
  }
}

const appiumURL = new URL(process.env.FAO_APPIUM_URL ?? "http://127.0.0.1:4723/");
const wdaLocalPort = Number.parseInt(process.env.FAO_WDA_LOCAL_PORT ?? "8100", 10);
if (!Number.isInteger(wdaLocalPort) || wdaLocalPort < 1024 || wdaLocalPort > 64535) {
  throw new Error("FAO_WDA_LOCAL_PORT must be between 1024 and 64535.");
}

const capabilities = {
  platformName: "iOS",
  "appium:automationName": "XCUITest",
  "appium:udid": process.env.FAO_DEVICE_ID,
  "appium:bundleId": "dev.fieldapporchestrator.mock-task",
  "appium:noReset": true,
  "appium:forceAppLaunch": true,
  "appium:shouldTerminateApp": true,
  "appium:useNewWDA": false,
  "appium:xcodeOrgId": process.env.FAO_DEVELOPMENT_TEAM,
  "appium:xcodeSigningId": "Apple Development",
  "appium:updatedWDABundleId": "dev.fieldapporchestrator.WebDriverAgentRunner",
  "appium:allowProvisioningDeviceRegistration": true,
  "appium:derivedDataPath": `/private/tmp/field-appium-wda-${wdaLocalPort}`,
  "appium:wdaLocalPort": wdaLocalPort,
  "appium:mjpegServerPort": wdaLocalPort + 1000,
  "appium:wdaLaunchTimeout": 120000,
  "appium:wdaConnectionTimeout": 60000,
  "appium:wdaStartupRetries": 3,
  "appium:wdaStartupRetryInterval": 20000,
  "appium:newCommandTimeout": 600,
  "appium:processArguments": {
    args: ["-mockDurationSeconds", "60"],
    env: {}
  }
};

let sessionID;

async function request(method, path, body) {
  const url = new URL(path.replace(/^\//, ""), appiumURL);
  const response = await fetch(url, {
    method,
    headers: body === undefined ? undefined : { "content-type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body)
  });
  const payload = await response.json();
  if (!response.ok || payload.value?.error) {
    const message = payload.value?.message ?? `${response.status} ${response.statusText}`;
    throw new Error(`${method} ${path} failed: ${message}`);
  }
  return payload.value;
}

async function findElement(accessibilityID, timeoutMilliseconds = 10000) {
  const deadline = Date.now() + timeoutMilliseconds;
  let lastError;
  while (Date.now() < deadline) {
    try {
      const value = await request("POST", `/session/${sessionID}/element`, {
        using: "accessibility id",
        value: accessibilityID
      });
      return value["element-6066-11e4-a52e-4f735466cecf"];
    } catch (error) {
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  }
  throw lastError ?? new Error(`Element ${accessibilityID} did not appear.`);
}

async function click(accessibilityID) {
  const elementID = await findElement(accessibilityID);
  await request("POST", `/session/${sessionID}/element/${elementID}/click`, {});
}

try {
  const session = await request("POST", "/session", {
    capabilities: { alwaysMatch: capabilities }
  });
  sessionID = session.sessionId;
  console.log("Persistent WebDriverAgent session started.");

  await findElement("home-screen");
  await click("featured-card-mock-task");
  await click("record-start-task");
  await findElement("recording-screen");
  await click("record-stop-task");
  await findElement("home-screen");

  console.log("Mock start, stop, and return-home flow passed through Appium.");
} finally {
  if (sessionID) {
    await request("DELETE", `/session/${sessionID}`);
  }
}
