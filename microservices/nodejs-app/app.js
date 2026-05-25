const express = require("express");
const app = express();
const PORT = process.env.PORT || 3000;
const VERSION = process.env.APP_VERSION || "1.0.0";

app.use(express.json());

app.get("/", (req, res) => {
  res.json({ service: "nodejs-app", status: "running", version: VERSION });
});

app.get("/health", (req, res) => {
  res.json({ status: "healthy" });
});

app.get("/api/data", (req, res) => {
  res.json({
    service: "nodejs-app",
    message: "Hello from the Node.js microservice!",
    version: VERSION,
  });
});

app.listen(PORT, () => {
  console.log(`Node.js app running on port ${PORT}`);
});
