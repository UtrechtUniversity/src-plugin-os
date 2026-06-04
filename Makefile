.DEFAULT_GOAL := check

check:
	python3 -m venv --clear .venv
	.venv/bin/pip install -r requirements-dev.txt
	.venv/bin/yamllint -c .yamllint.yml .
	.venv/bin/detect-secrets scan --baseline .secrets.baseline
	.venv/bin/ansible-lint
	.venv/bin/ansible-playbook --syntax-check $(wildcard *.yml)
