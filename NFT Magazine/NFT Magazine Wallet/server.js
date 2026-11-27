const express = require("express");
const path = require("path");

const app = express();

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

const PDN_ADDRESS = "0x238B9b6De2A247178307d504e9B8DE5A98be4864";
const MAGAZINE_ADDRESS = "0xD51D05902Cc17D2609fD30c0c64fc8CEb50BCEFD";

app.get("/api/config", (req, res) => {
  res.json({
    pdnAddress: PDN_ADDRESS,
    magazineAddress: MAGAZINE_ADDRESS
  });
});

app.listen(8788, "127.0.0.1", () => {
  console.log("PDN NFT Magazine: http://127.0.0.1:8788");
});
