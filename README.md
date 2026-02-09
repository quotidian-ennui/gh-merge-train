# gh-merge-train

It's a fake merge train; when a merge queue is too much

This is because some of the repositories I'm involved in have _required actions that take a while to execute_ and ostensibly we want to queue up a list of PRs that needed rebasing and then squash-merging. Of course we could use merge queues, but this _was too much effort_ to manage in the short term.

Thus a fake merge-train was born. It's of marginal use if your actions are fast, but when you have a monorepo where the integration tests take a few minutes this could reduce some toil.

> It is a direct lift and shift of
> - https://github.com/quotidian-ennui/ghcli-utils/pull/1
> - https://github.com/quotidian-ennui/ghcli-utils/pull/2
> - https://github.com/quotidian-ennui/ghcli-utils/pull/3


## Installation

- [GitHub CLI](https://cli.github.com/) is already installed and authenticated
- [gh-squash-merge](https://github.com/quotidian-ennui/gh-squash-merge) extension
- `gh extension install quotidian-ennui/gh-merge-train`

### Usage

```text
bsh ❯ gh merge-train

Usage: gh merge-train [flags] [pr_number...]

This is a fake merge train that rebases, approves, and squash-merges each argument

In effect it takes some toil out of your life because we end up with this:

gh-merge-train 25 26 27
for PR in 25 26 27 do
  gh pr update-branch PR --rebase
  while in_progress do
    gh pr checks PR --json "state,name" | jq -c ".[]" etc.
  done
  if success then
    gh pr review --approve PR
    gh squash-merge PR --use-default-msg
  fi
done

Flags
  -m, --merge merge rather than rebase when updating the pr branch

env:
  GH_MERGE_TRAIN_MAX_ATTEMPTS      : [5] : how many times to attempt an update
  GH_MERGE_TRAIN_BOT_LABEL         : [] : optional label to apply to a bot PR.
  GH_MERGE_TRAIN_DEPENDABOT_REBASE : [] : optional use dependabot chat-ops to rebase if appropriate.
```

#### Environment Variables

- `GH_MERGE_TRAIN_MAX_ATTEMPTS` -> the max attempts to attempt to update the PR; defaults to 5 if not set.
- `GH_MERGE_TRAIN_BOT_LABEL` -> an optional label that you want to apply to PRs that were raised by a bot (e.g. dependabot)
- `GH_MERGE_TRAIN_DEPENDABOT_REBASE` -> use `@dependabot rebase` when updating the PR; if it is a dependabot created PR.

### Bonus Chatter

There are reasons for the `GH_MERGE_TRAIN_BOT_LABEL` and `GH_MERGE_TRAIN_DEPENDABOT_REBASE` environment variables

`GH_MERGE_TRAIN_BOT_LABEL` is because we did not want dependabot to trigger expensive builds; we only want to run the expensive builds after we have reviewed the dependency before merging. Dependabot _can be quite eager_ about rebasing so this avoids a chain of expensive builds that run without our intervention.

`GH_MERGE_TRAIN_DEPENDABOT_REBASE` is because, dependabot can do a _more appropriate thing_ when attempting to update a PR; it's subtly better than trying to do a `gh pr update-branch --rebase` in some usecases. If you are finding that, then setting this flag to be true will be your friend but you are going to be beholden to dependabot's scheduling.
