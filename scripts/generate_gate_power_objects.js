// Generate an XSim Tcl list containing top-level ports and every standard-cell
// output pin in a flat Yosys gate netlist.  OpenSTA's VCD reader maps
// hierarchical instance pins, whereas dumping only connecting net names
// annotates primary ports but not internal cell activity.

const fs = require("fs");
const path = require("path");

if (process.argv.length !== 5) {
  process.stderr.write(
    "usage: node generate_gate_power_objects.js <netlist.v> <std_cell_dir> <output.tcl>\n"
  );
  process.exit(2);
}

const netlistPath = process.argv[2];
const libraryDir = process.argv[3];
const outputPath = process.argv[4];
const scope = "/winograd_chip_1000_tb/dut";

const outputPortsByModule = new Map();
for (const fileName of fs.readdirSync(libraryDir).filter((name) => name.endsWith(".v"))) {
  const text = fs.readFileSync(path.join(libraryDir, fileName), "utf8");
  const moduleRe = /module\s+(\w+)\s*\([^;]*\);([\s\S]*?)endmodule/g;
  let moduleMatch;
  while ((moduleMatch = moduleRe.exec(text)) !== null) {
    const outputs = new Set();
    const outputRe = /\boutput\b\s+(?:wire\s+|reg\s+)?(?:\[[^\]]+\]\s*)?([^;]+);/g;
    let outputMatch;
    while ((outputMatch = outputRe.exec(moduleMatch[2])) !== null) {
      for (const name of outputMatch[1].split(",")) {
        const cleanName = name.trim().split(/\s+/).pop();
        if (cleanName) outputs.add(cleanName);
      }
    }
    if (outputs.size > 0) outputPortsByModule.set(moduleMatch[1], outputs);
  }
}

const netlist = fs.readFileSync(netlistPath, "utf8");
const topHeader = netlist.match(/module\s+chip\s*\(([^;]+)\);/);
if (!topHeader) throw new Error("module chip header not found");

const objectPaths = topHeader[1]
  .split(",")
  .map((name) => `${scope}/${name.trim()}`);

const instanceRe = /^\s*(\w+)\s+(\S+)\s*\(([\s\S]*?)^\s*\);/gm;
let instanceMatch;
let instanceCount = 0;
let outputPinCount = 0;
while ((instanceMatch = instanceRe.exec(netlist)) !== null) {
  const moduleName = instanceMatch[1];
  const instanceName = instanceMatch[2];
  const outputPorts = outputPortsByModule.get(moduleName);
  if (!outputPorts) continue;

  instanceCount += 1;
  const connectionRe = /\.(\w+)\s*\(/g;
  let connectionMatch;
  while ((connectionMatch = connectionRe.exec(instanceMatch[3])) !== null) {
    if (outputPorts.has(connectionMatch[1])) {
      // A leading backslash is Verilog's escaped-identifier marker, not part
      // of the elaborated XSim instance name.
      const xsimInstanceName = instanceName.replace(/^\\/, "");
      objectPaths.push(`${scope}/${xsimInstanceName}/${connectionMatch[1]}`);
      outputPinCount += 1;
    }
  }
}

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, `${objectPaths.join("\n")}\n`);
process.stdout.write(
  `Generated ${outputPath}: ${instanceCount} cells, ${outputPinCount} output pins\n`
);
