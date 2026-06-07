venv := ".venv"
python := venv + "/bin/python"
flask := venv + "/bin/flask"
alembic := venv + "/bin/alembic"
pytest := venv + "/bin/pytest"

install:
    python3 -m venv {{venv}}
    {{python}} -m pip install -q -e ".[dev]"

migrate: install
    {{alembic}} upgrade head

run: migrate
    {{flask}} --app src/statement_importer/web/app run --debug

test: install
    {{pytest}} tests/ -v
