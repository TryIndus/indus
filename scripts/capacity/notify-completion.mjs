const apiUrl = (repository, page) =>
  `https://api.github.com/repos/${repository}/issues?state=all&per_page=100&page=${page}`;

async function checkedJson(response) {
  if (!response.ok) throw new Error(`GitHub issue request failed with HTTP ${response.status}.`);
  return response.json();
}

export async function findCompletionIssue({ fetchImpl, repository, token, title }) {
  for (let page = 1; ; page += 1) {
    const issues = await checkedJson(await fetchImpl(apiUrl(repository, page), {
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json' },
    }));
    if (!Array.isArray(issues)) throw new Error('GitHub returned an invalid issue list.');
    const match = issues.find((issue) => !issue.pull_request && issue.title === title);
    if (match) return match;
    if (issues.length < 100) return null;
  }
}

export async function ensureCompletionIssue({ fetchImpl = fetch, repository, token, targetId, desired, assignee, result, runUrl }) {
  if (!repository || !token || !targetId || !desired || !runUrl || !['applied', 'no-op'].includes(result)) {
    throw new Error('Missing or invalid completion-notification configuration.');
  }
  const title = `Capacity target reached: ${targetId} -> ${desired}`;
  const lookup = () => findCompletionIssue({ fetchImpl, repository, token, title });
  const existing = await lookup();
  if (existing) return { status: 'existing', url: existing.html_url };

  const body = `${targetId} is at its approved size (${desired}). ${result === 'applied' ? 'This run applied the change.' : 'This run verified the existing size.'} Verify service health and Terraform state. Workflow run: ${runUrl}`;
  let response;
  try {
    response = await fetchImpl(`https://api.github.com/repos/${repository}/issues`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        Accept: 'application/vnd.github+json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ title, body, ...(assignee ? { assignees: [assignee] } : {}) }),
    });
    const created = await checkedJson(response);
    return { status: 'created', url: created.html_url };
  } catch (error) {
    // A lost response can follow a successful create. Check before retrying next run.
    const created = await lookup();
    if (created) return { status: 'existing', url: created.html_url };
    throw error;
  }
}

if (process.argv[1]?.endsWith('/notify-completion.mjs')) {
  try {
    const result = await ensureCompletionIssue({
      repository: process.env.GITHUB_REPOSITORY,
      token: process.env.GH_TOKEN,
      targetId: process.env.TARGET_ID,
      desired: process.env.TARGET_DESIRED,
      assignee: process.env.ASSIGNEE,
      result: process.env.RESULT,
      runUrl: `${process.env.GITHUB_SERVER_URL}/${process.env.GITHUB_REPOSITORY}/actions/runs/${process.env.GITHUB_RUN_ID}`,
    });
    console.log(`Completion issue ${result.status}: ${result.url}`);
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
