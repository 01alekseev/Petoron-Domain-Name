const express = require("express");
const path = require("path");

const app = express();

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

const PDN_ADDRESS = "0x238B9b6De2A247178307d504e9B8DE5A98be4864";
const MARKET_ADDRESS = "0x458293FfE82f370e43b1A49F5eb09d0a01B215eB";

app.get("/api/config", (req, res) => {
  res.json({
    pdnAddress: PDN_ADDRESS,
    marketAddress: MARKET_ADDRESS
  });
});

app.listen(8788, "127.0.0.1", () => {
  console.log("PDN Client: http://127.0.0.1:8788");
});
