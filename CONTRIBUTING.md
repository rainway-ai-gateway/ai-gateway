# Contribute Code

You are welcome to contribute to the AI Gateway ecosystem.
To contribute, you need to agree to the
[Contributor License Agreement](https://cla-assistant.io/rainway-ai-gateway/ai-gateway).

We sincerely appreciate your contribution. This document explains the suggested workflow and code review expectations.

## Workflow

We generally follow a Git branching model similar to:
http://nvie.com/posts/a-successful-git-branching-model/

Typical steps:

1. Fork

  Our community grows quickly; please submit Pull Requests from your fork.
  To create a fork, go to the GitHub page and click the
  ["Fork" button](https://help.github.com/articles/fork-a-repo/).

2. Clone

  ```bash
  git clone https://github.com/<your-github-account>/ai-gateway
  cd ai-gateway
  ```

3. Create a local feature branch

  ```bash
  git checkout -b my-cool-stuff
  ```

4. Build and test

  ```bash
  make docker-standalone
  ```

5. Keep pulling from upstream

  Pull from the official repo often so you can resolve conflicts early.

  ```bash
  git remote add upstream https://github.com/rainway-ai-gateway/ai-gateway
  git pull upstream main
  ```

6. Push and open a Pull Request

  ```bash
  git push origin my-cool-stuff
  ```

  Then open a Pull Request:
  https://help.github.com/articles/creating-a-pull-request/

  If your change fixes an issue, include "Fixes <issue-URL>" in the PR description:
  https://help.github.com/articles/closing-issues-using-keywords/

7. Delete local and remote branches (optional)

  ```bash
  git push origin :my-cool-stuff
  git checkout main
  git pull upstream main
  git branch -d my-cool-stuff
  ```

## Code Review

- Feel free to ping reviewers after CI passes.
- Please respond to every review comment.
- Prefer a clean history: avoid too many trivial commits; consider `git commit --amend` when appropriate.

## Coding Standard

### Code Style

Our Go code follows the Go style guide:
https://github.com/golang/go/wiki/Style

### Unit Tests

Please add relevant unit tests when changing code.
For Go code, use the standard `testing` package:
https://golang.org/pkg/testing/
