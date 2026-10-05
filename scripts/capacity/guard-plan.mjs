import { readFileSync } from 'node:fs';

export function evaluatePlan(plan, target) {
  const sideEffects = typeof target.side_effects === 'string'
    ? JSON.parse(target.side_effects)
    : (target.side_effects ?? {});
  const changes = (plan.resource_changes ?? []).filter(
    (resource) => resource.change.actions.some((action) => action !== 'no-op'),
  );

  if (changes.length === 0) {
    const resource = (plan.resource_changes ?? []).find((entry) => entry.address === target.address);
    if (resource?.type !== target.type || resource.change.after?.[target.attribute] !== target.desired
      || Object.entries(sideEffects).some(([key, value]) => resource.change.after[key] !== value)) {
      throw new Error('The target is missing or its configured size differs from the approved value.');
    }
    return 'no-op';
  }
  if (changes.length !== 1) throw new Error('The plan changes more than one resource.');

  const resource = changes[0];
  if (resource.address !== target.address || resource.type !== target.type) {
    throw new Error('The plan changes a resource outside the approved target.');
  }
  if (resource.mode !== 'managed' || resource.change.actions.join(',') !== 'update') {
    throw new Error('The target must have one in-place update, with no replacement.');
  }

  const { before, after, after_unknown: unknown } = resource.change;
  if (!before || !after || typeof before !== 'object' || typeof after !== 'object') {
    throw new Error('The plan does not contain a complete before/after comparison.');
  }
  if (!(target.attribute in before) || after[target.attribute] !== target.desired) {
    throw new Error('The size attribute does not match the approved desired value.');
  }
  if (before[target.attribute] === after[target.attribute]) {
    throw new Error('The approved size attribute is unchanged.');
  }

  const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
  for (const key of keys) {
    if (key !== target.attribute && JSON.stringify(before[key]) !== JSON.stringify(after[key])
      && (!(key in sideEffects) || after[key] !== sideEffects[key])) {
      throw new Error(`The plan also changes ${key}.`);
    }
  }
  if (Object.entries(sideEffects).some(([key, value]) => after[key] !== value)) {
    throw new Error('An approved scheduling value is missing from the plan.');
  }
  if (unknown && Object.values(unknown).some((value) => value === true)) {
    throw new Error('The plan has an unknown post-apply value.');
  }

  return 'apply';
}

export function isCapacityOnlyFailure(log, retryCodes) {
  const errors = [...log.matchAll(/^Error: (.+)$/gm)].map((match) => match[1]);
  return errors.length === 1 && retryCodes.some((code) => errors[0].includes(code));
}

if (process.argv[1]?.endsWith('/guard-plan.mjs')) {
  const [mode, file, configuration] = process.argv.slice(2);
  try {
    const target = JSON.parse(configuration);
    if (mode === 'plan') {
      console.log(evaluatePlan(JSON.parse(readFileSync(file, 'utf8')), target));
    } else if (mode === 'capacity-error') {
      console.log(isCapacityOnlyFailure(readFileSync(file, 'utf8'), JSON.parse(target.retry_codes)) ? 'retry' : 'fail');
    } else {
      throw new Error('Expected plan or capacity-error mode.');
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
