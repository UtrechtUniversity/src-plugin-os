.DEFAULT_GOAL := lint

lint:
	uv sync --group dev
	uv run yamllint -c .yamllint.yml .
	uv run ansible-lint
	uv run detect-secrets scan --all-files --baseline .secrets.baseline
	uv run ansible-playbook --syntax-check $(wildcard *.yml)
