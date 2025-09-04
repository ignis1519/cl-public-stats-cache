VENV_DIR=.venv
REQ_FILE=requirements.txt
PYTHON=python3

.PHONY: venv install run clean freeze

venv:
	$(PYTHON) -m venv $(VENV_DIR)

install: venv
	$(VENV_DIR)/bin/pip install --upgrade pip
	$(VENV_DIR)/bin/pip install -r $(REQ_FILE)

freeze:
	$(VENV_DIR)/bin/pip freeze > $(REQ_FILE)

run: install
	$(VENV_DIR)/bin/python /Users/asaavedra/_wp/ineaggregator/main.py

clean:
	rm -rf $(VENV_DIR)