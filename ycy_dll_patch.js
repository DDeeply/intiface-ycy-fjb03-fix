/**
 * Yiciyuan YCY-FJB-03 Hot-patcher for rust_lib_intiface_central.dll
 * 
 * Modifies the yiciyuan protocol frame generator in rust_lib_intiface_central.dll:
 * 1. Changes buffer allocation from 16 bytes to 6 bytes.
 * 2. Writes the 6-byte frame [0x35, 0x12, stroke, vibe, axis_c, checksum]
 *    where checksum = (0x35 + 0x12 + stroke + vibe + axis_c) & 0xFF.
 * 3. Updates the Vec length and capacity to 6 bytes.
 * 
 * Usage:
 *   node ycy_dll_patch.js <path-to-rust_lib_intiface_central.dll>
 */

const fs = require("fs");
const path = require("path");

const dllPath = process.argv[2];
if (!dllPath || !fs.existsSync(dllPath)) {
  console.error("ERROR: DLL path not specified or file not found.");
  process.exit(1);
}

const bakPath = dllPath + ".bak";
const offAlloc = 0x84112d;
const offCode = 0x841145;

const originalAlloc = Buffer.from([0xb9, 0x10, 0x00, 0x00, 0x00]);
const patchedAlloc  = Buffer.from([0xb9, 0x06, 0x00, 0x00, 0x00]);

const originalCode = Buffer.from([
  0x66, 0xc7, 0x00, 0x35, 0x12,
  0x0f, 0xb6, 0x0f, 0x88, 0x48, 0x02,
  0x0f, 0xb6, 0x4f, 0x01, 0x88, 0x48, 0x03,
  0x0f, 0xb6, 0x4f, 0x02, 0x88, 0x48, 0x04,
  0x48, 0xc7, 0x45, 0x00, 0x10, 0x00, 0x00, 0x00,
  0x48, 0x89, 0x45, 0x08,
  0x48, 0xc7, 0x45, 0x10, 0x10, 0x00, 0x00, 0x00
]);

const patchedCode = Buffer.from([
  0x66, 0xc7, 0x00, 0x35, 0x12,   // mov word ptr [rax], 0x1235 (header 0x35 0x12)
  0x8b, 0x17,                      // mov edx, dword ptr [rdi]   (load stroke & vibe)
  0x66, 0x89, 0x50, 0x02,          // mov word ptr [rax+2], dx   (write byte 2 & byte 3)
  0x8a, 0x4f, 0x02,                // mov cl, byte ptr [rdi+2]   (load axis_c)
  0x88, 0x48, 0x04,                // mov byte ptr [rax+4], cl   (write byte 4)
  0x00, 0xf2,                      // add dl, dh                 (stroke + vibe)
  0x00, 0xca,                      // add dl, cl                 (+ axis_c)
  0x80, 0xc2, 0x47,                // add dl, 0x47               (+ 0x35 + 0x12)
  0x88, 0x50, 0x05,                // mov byte ptr [rax+5], dl   (write checksum)
  0x48, 0x89, 0x45, 0x08,          // mov qword ptr [rbp+8], rax (save buffer ptr)
  0x6a, 0x06,                      // push 6
  0x5a,                            // pop rdx
  0x48, 0x89, 0x55, 0x00,          // mov qword ptr [rbp], rdx   (set cap = 6)
  0x48, 0x89, 0x55, 0x10,          // mov qword ptr [rbp+16], rdx(set len = 6)
  0x90, 0x90, 0x90                 // nop nop nop
]);

const dll = fs.readFileSync(dllPath);
const curAlloc = dll.subarray(offAlloc, offAlloc + 5);
const curCode  = dll.subarray(offCode,  offCode  + originalCode.length);

if (curAlloc.equals(patchedAlloc) && curCode.equals(patchedCode)) {
  console.log("ALREADY_PATCHED");
  process.exit(0);
}

if (curAlloc.equals(originalAlloc) && curCode.equals(originalCode)) {
  if (!fs.existsSync(bakPath)) {
    fs.copyFileSync(dllPath, bakPath);
  }
  patchedAlloc.copy(dll, offAlloc);
  patchedCode.copy(dll, offCode);
  fs.writeFileSync(dllPath, dll);

  const verified = fs.readFileSync(dllPath);
  const ok = verified.subarray(offAlloc, offAlloc + 5).equals(patchedAlloc) &&
             verified.subarray(offCode, offCode + patchedCode.length).equals(patchedCode);
  if (ok) {
    console.log("PATCH_APPLIED");
    process.exit(0);
  } else {
    console.error("VERIFY_FAILED");
    process.exit(2);
  }
}

console.error("VERSION_MISMATCH");
console.error("Found alloc: " + curAlloc.toString("hex"));
console.error("Found code:  " + curCode.toString("hex"));
process.exit(3);
