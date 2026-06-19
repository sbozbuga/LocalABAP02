import fs from 'fs';
import { Registry, MemoryFile, Issue, Config } from '@abaplint/core';

async function run() {
  const reg = new Registry();
  const file1 = new MemoryFile(
    '#ctdi#cl_print_driver_base.clas.abap',
    fs.readFileSync('src/#ctdi#cl_print_driver_base.clas.abap', 'utf8')
  );
  const file2 = new MemoryFile(
    '#ctdi#cl_print_cust_engine.clas.abap',
    fs.readFileSync('src/#ctdi#cl_print_cust_engine.clas.abap', 'utf8')
  );

  const defaultConf = Config.getDefault().get();
  const customConf = JSON.parse(fs.readFileSync('abaplint.json', 'utf8'));
  
  if (customConf.global) Object.assign(defaultConf.global, customConf.global);
  if (customConf.syntax) Object.assign(defaultConf.syntax, customConf.syntax);
  if (customConf.rules) Object.assign(defaultConf.rules, customConf.rules);
  
  const config = new Config(JSON.stringify(defaultConf));
  reg.setConfig(config);

  reg.addFile(file1);
  reg.addFile(file2);

  await reg.parseAsync();
  const issues = reg.findIssues();

  for (const issue of issues) {
    console.log(`${issue.getFilename()} [${issue.getStart().getRow()}, ${issue.getStart().getCol()}]: (${issue.getKey()}) ${issue.getMessage()}`);
  }
  
  console.log(`Found ${issues.length} issues.`);
}

run().catch(console.error);
