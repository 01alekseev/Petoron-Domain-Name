const express = require("express");
const path = require("path");

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

const PDN_ADDRESS = process.env.PDN_ADDRESS || "0x238B9b6De2A247178307d504e9B8DE5A98be4864";
const DEX_ADDRESS = process.env.DEX_ADDRESS || "0x7ea5CAE1262924A97433662b1B8bE002f4DdA6fb";

app.get("/api/config", (req, res) => {
  res.json({ pdnAddress: PDN_ADDRESS, dexAddress: DEX_ADDRESS });
});

app.listen(8788, "127.0.0.1", () => {
  console.log("PDN DEX Local Client: http://127.0.0.1:8788");
});
