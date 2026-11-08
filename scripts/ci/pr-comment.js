// Create or update the pull request comment identified by a hidden marker, so each project
// keeps a single comment that is refreshed on every push instead of piling up new ones.
// Used from actions/github-script: require('./scripts/ci/pr-comment.js')({ github, context, ... }).
const fs = require('fs');

module.exports = async ({ github, context, marker, file, onlyIfExists = false }) => {
  const tag = `<!-- lz-engine:${marker} -->`;
  const text = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : 'No report was produced. See the job logs.';
  const run = `${context.serverUrl}/${context.repo.owner}/${context.repo.repo}/actions/runs/${context.runId}`;
  const body = `${tag}\n${text.slice(0, 64000)}\n\n<sub>[Workflow run](${run}) · commit ${context.sha.slice(0, 7)}</sub>`;

  const params = { ...context.repo, issue_number: context.issue.number };
  const comments = await github.paginate(github.rest.issues.listComments, { ...params, per_page: 100 });
  const existing = comments.find((c) => c.user?.type === 'Bot' && c.body?.startsWith(tag));

  if (existing) {
    await github.rest.issues.updateComment({ ...context.repo, comment_id: existing.id, body });
  } else if (!onlyIfExists) {
    await github.rest.issues.createComment({ ...params, body });
  }
};
