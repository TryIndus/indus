import { readFileSync } from 'node:fs';

export function assertNoPendingRdsChanges(response, instanceId) {
  const instances = response?.DBInstances;
  if (!Array.isArray(instances) || instances.length !== 1
    || instances[0]?.DBInstanceIdentifier !== instanceId) {
    throw new Error('RDS did not return the expected DB instance.');
  }

  const pending = instances[0].PendingModifiedValues;
  if (pending !== undefined && pending !== null
    && (typeof pending !== 'object' || Array.isArray(pending) || Object.keys(pending).length > 0)) {
    throw new Error('RDS has pending modifications; refusing to apply them immediately.');
  }
}

if (process.argv[1]?.endsWith('/rds-preflight.mjs')) {
  try {
    assertNoPendingRdsChanges(JSON.parse(readFileSync(0, 'utf8')), process.argv[2]);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
