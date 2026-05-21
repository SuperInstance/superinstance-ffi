// Test when WASM is built
const tests = [
  { name: "eisenstein_norm(3,5)", expected: 3*3 - 3*5 + 5*5 },
  { name: "laman_edges(12)", expected: 21 },
  { name: "is_rigid(12,21)", expected: true },
  { name: "deadband(50.1, 50.0, 0.5)", expected: 50.0 },
];

console.log("SuperInstance Math WASM Tests");
console.log("=" + "=".repeat(40));
tests.forEach(t => console.log(`  ${t.name} = ${t.expected}`));
console.log("Tests defined. Run 'wasm-pack build --target nodejs' first.");
