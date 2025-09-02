import os
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
from bigquery_client import fetch_similar_issues, insert_new_ticket

# ==========================
# Flask App Configuration
# ==========================

# Define the absolute path to the frontend folder
FRONTEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "../frontend"))

# Create Flask app instance
# static_folder → where static files (HTML, CSS, JS) are stored
# static_url_path → ensures correct URL mapping for static assets
app = Flask(
    __name__,
    static_folder=FRONTEND_DIR,
    static_url_path=""
)

# Enable Cross-Origin Resource Sharing (CORS)
# This allows frontend (running on a different port) to communicate with the Flask backend
CORS(app)

# ==========================
# Routes to Serve Frontend
# ==========================

@app.route("/")
def index():
    """
    Serves the main index.html file when a user visits the root URL.
    Example → http://127.0.0.1:5000/
    """
    return send_from_directory(FRONTEND_DIR, "index.html")


@app.route("/<path:path>")
def static_files(path):
    """
    Serves other frontend static files (CSS, JS, images, etc.).
    Example → http://127.0.0.1:5000/style.css
    """
    return send_from_directory(FRONTEND_DIR, path)

# ==========================
# API Endpoints
# ==========================

@app.route("/search", methods=["POST"])
def search():
    """
    Endpoint to fetch top 5 similar issues from BigQuery.

    Expected Request Body:
        {
            "title": "Issue title",
            "description": "Issue description"
        }

    Returns:
        JSON array of matching issues with:
            - id
            - title
            - clean_question_body
            - clean_answer_body
            - distance
    """
    data = request.json
    title = data.get("title", "")
    description = data.get("description", "")

    # Fetch matching issues from BigQuery using embeddings
    results = fetch_similar_issues(title, description)

    return jsonify(results)


@app.route("/feedback", methods=["POST"])
def feedback():
    """
    Endpoint to handle user feedback.

    - If 'helpful' is True → Do nothing, just acknowledge.
    - If 'helpful' is False → Insert the new issue into BigQuery for future training.

    Expected Request Body:
        {
            "helpful": false,
            "title": "Issue title",
            "description": "Issue description"
        }

    Returns:
        JSON response: {"status": "ok"}
    """
    data = request.json
    helpful = data.get("helpful", True)

    # If issue wasn't helpful, insert it into database for future use
    if not helpful:
        title = data.get("title")
        description = data.get("description")
        insert_new_ticket(title, description)

    return jsonify({"status": "ok"})

# ==========================
# Run Flask Application
# ==========================

if __name__ == "__main__":
    # Debug=True → Enables hot reload and detailed error logs
    app.run(debug=True)
