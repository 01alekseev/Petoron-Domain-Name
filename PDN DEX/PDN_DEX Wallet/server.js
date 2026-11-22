const express = require("express");
const path = require("path");

const app = express();
app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

const PDN_ADDRESS = process.env.PDN_ADDRESS || "0x238B9b6De2A247178307d504e9B8DE5A98be4864";
const DEX_ADDRESS = process.env.DEX_ADDRESS || "0xFE24B65c46641C7f4Cb6b1a603D6dc2BB6a0200E";

app.get("/api/config", (req, res) => {
  res.json({ pdnAddress: PDN_ADDRESS, dexAddress: DEX_ADDRESS });
});

app.listen(8788, "127.0.0.1", () => {
  console.log("PDN DEX Local Client: http://127.0.0.1:8788");
});
