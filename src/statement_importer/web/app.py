import os
import shutil
import tempfile

from flask import Flask, g, redirect, render_template, request, session, url_for
from werkzeug.utils import secure_filename

import statement_importer as si

DB_PATH = os.environ.get("STATEMENT_IMPORTER_DB", "statement_importer.db")


def create_app():
    app = Flask(__name__, template_folder="templates")
    app.secret_key = os.environ.get("FLASK_SECRET_KEY", "dev-secret-change-me")

    si.init_db(DB_PATH)

    @app.before_request
    def open_db():
        g.db = si.get_session()

    @app.teardown_request
    def close_db(exc):
        db = g.pop("db", None)
        if db is not None:
            db.close()

    # -------------------------------------------------------------------------
    # Root
    # -------------------------------------------------------------------------

    @app.get("/")
    def index():
        return redirect(url_for("accounts_list"))

    # -------------------------------------------------------------------------
    # Masterdata — Accounts
    # -------------------------------------------------------------------------

    @app.get("/masterdata/accounts")
    def accounts_list():
        accounts = si.get_all_accounts(g.db)
        return render_template("masterdata/accounts.html", accounts=accounts)

    @app.get("/masterdata/accounts/new")
    def accounts_new():
        specs = si.discover_specs()
        return render_template("masterdata/account_form.html", account=None, specs=specs)

    @app.post("/masterdata/accounts/new")
    def accounts_create():
        name = request.form["name"].strip()
        currency = request.form["currency"].strip().upper()
        spec = request.form.get("mapping_spec") or None
        si.create_account(g.db, name=name, currency=currency, mapping_spec=spec)
        return redirect(url_for("accounts_list"))

    @app.get("/masterdata/accounts/<int:account_id>/edit")
    def accounts_edit(account_id):
        account = si.get_account(g.db, account_id)
        specs = si.discover_specs()
        return render_template("masterdata/account_form.html", account=account, specs=specs)

    @app.post("/masterdata/accounts/<int:account_id>/edit")
    def accounts_update(account_id):
        name = request.form["name"].strip()
        currency = request.form["currency"].strip().upper()
        spec = request.form.get("mapping_spec") or None
        si.update_account(g.db, account_id, name=name, currency=currency, mapping_spec=spec)
        return redirect(url_for("accounts_list"))

    # -------------------------------------------------------------------------
    # Import
    # -------------------------------------------------------------------------

    @app.get("/import/upload")
    def import_upload():
        return render_template("import/upload.html")

    @app.post("/import/upload")
    def import_upload_post():
        files = request.files.getlist("files")
        upload_dir = tempfile.mkdtemp(prefix="stmt_")
        saved = []
        for f in files:
            if not f.filename:
                continue
            fname = secure_filename(f.filename)
            dest = os.path.join(upload_dir, fname)
            f.save(dest)
            saved.append({"name": fname, "path": dest})
        session["upload_dir"] = upload_dir
        session["uploaded_files"] = saved
        return redirect(url_for("import_assign"))

    @app.get("/import/assign")
    def import_assign():
        uploaded = session.get("uploaded_files", [])
        accounts = si.get_all_accounts(g.db)
        return render_template("import/assign.html", files=uploaded, accounts=accounts)

    @app.post("/import/assign")
    def import_assign_post():
        uploaded = session.get("uploaded_files", [])
        results = []
        for i, file_info in enumerate(uploaded):
            acct_id = int(request.form[f"account_{i}"])
            account = si.get_account(g.db, acct_id)
            try:
                txs = si.import_csv(
                    g.db, file_info["path"], account, source_file=file_info["name"]
                )
                results.append({"name": file_info["name"], "count": len(txs), "error": None})
            except Exception as e:
                results.append({"name": file_info["name"], "count": 0, "error": str(e)})

        shutil.rmtree(session.pop("upload_dir", ""), ignore_errors=True)
        session.pop("uploaded_files", None)
        return render_template("import/results.html", results=results)

    # -------------------------------------------------------------------------
    # Process
    # -------------------------------------------------------------------------

    @app.get("/process")
    def process():
        transactions = si.get_transactions(g.db, status="pending")
        accounts = {a.id: a for a in si.get_all_accounts(g.db)}
        return render_template("process/index.html", transactions=transactions, accounts=accounts)

    return app


app = create_app()
