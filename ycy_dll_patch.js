/**
 * Yiciyuan YCY-FJB-03 Hot-patcher for rust_lib_intiface_central.dll
 * 
 * Version: 1.1.0 (Dynamic Signature Scanning)
 * 
 * Automatically scans and patches the yiciyuan protocol frame generator:
 * 1. Locates the 45-byte instruction block via dynamic pattern matching
 *    (independent of Intiface Central build version or code offsets).
 * 2. Changes buffer allocation from 16 bytes to 6 bytes.
 * 3. Writes the 6-byte frame [0x35, 0x12, stroke, vibe, axis_c, checksum]
 *    where checksum = (0x35 + 0x12 + stroke + vibe + axis_c) & 0xFF.
 * 4. Updates Vec length and capacity to 6 bytes.
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

function findAll(haystack, needle) {
  const hits = [];
  let i = haystack.indexOf(needle, 0);
  while (i !== -1) {
    hits.push(i);
    i = haystack.indexOf(needle, i + 1);
  }
  return hits;
}

const dll = fs.readFileSync(dllPath);

const origHits    = findAll(dll, originalCode);
const patchedHits = findAll(dll, patchedCode);

// Check if already patched
if (origHits.length === 0 && patchedHits.length > 0) {
  console.log("ALREADY_PATCHED (found at 0x" + patchedHits[0].toString(16).toUpperCase() + ")");
  process.exit(0);
}

// Ensure unique signature match
if (origHits.length !== 1) {
  console.error("VERSION_MISMATCH");
  console.error("Original signature hits = " + origHits.length + ", patched hits = " + patchedHits.length);
  process.exit(3);
}

const offCode  = origHits[0];
const offAlloc = offCode - 0x18; // Distance between alloc instruction and frame generator is fixed (0x18 = 24 bytes)

if (offAlloc < 0 || !dll.subarray(offAlloc, offAlloc + 5).equals(originalAlloc)) {
  console.error("VERSION_MISMATCH");
  console.error("Code found at 0x" + offCode.toString(16) + " but alloc signature at 0x" + offAlloc.toString(16) + " mismatch.");
  process.exit(3);
}

console.log("Found unpatched target at 0x" + offCode.toString(16).toUpperCase() + ". Applying patch...");

if (!fs.existsSync(bakPath)) {
  fs.copyFileSync(dllPath, bakPath);
  console.log("Backup created at: " + bakPath);
}

patchedAlloc.copy(dll, offAlloc);
patchedCode.copy(dll, offCode);
fs.writeFileSync(dllPath, dll);

// Verify write
const verified = fs.readFileSync(dllPath);
const ok = verified.subarray(offAlloc, offAlloc + 5).equals(patchedAlloc) &&
           verified.subarray(offCode, offCode + patchedCode.length).equals(patchedCode);

if (ok) {
  console.log("PATCH_APPLIED (offset 0x" + offCode.toString(16).toUpperCase() + ")");
  process.exit(0);
} else {
  console.error("VERIFY_FAILED");
  process.exit(2);
}
