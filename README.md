# Duplicate Ticket Detection  
**Approach-2: Semantic Detective**  

A prototype system built using **BigQuery**, **Generative AI**, and **Embeddings** to detect **duplicate or similar issues/tickets**.  
This solution demonstrates how developers can **save time and effort** by checking if a reported issue already exists before creating a new one.

---

## 📌 Problem Statement  
In software development, developers often raise new tickets without checking if a similar one already exists.  
This leads to:  
- Wasted **man-hours**  
- **Repetitive work** and **reinventing the wheel**  
- Increased **operational costs**  

---

## 🎯 Objective  
To build a **semantic similarity detection system** that, given a new issue description:  
- Finds the **top 5 most similar tickets** already present in the database.  
- Suggests existing solutions where available.  
- Allows users to add the ticket as a **new entry** if no suitable match is found.  

---

## 💡 Business Impact  
- **Saves developer time** → Quickly find solutions from existing tickets.  
- **Reduces redundant work** → Avoid raising duplicate issues.  
- **Knowledge reusability** → Leverages existing solved tickets.  
- **Multi-lingual capability** → Works for companies worldwide, not just English-speaking ones.

---

## 🧠 Approach Overview  

### 1. Dataset  
- Used **StackOverflow's public dataset** available on **BigQuery**.  
- Two key tables:  
  - **`posts_questions`** → Contains questions/issues.  
  - **`posts_answers`** → Contains answers to those questions.  
- Extracted **10,000 questions** (limited due to free-tier credits) and fetched their **accepted answers**.

---

### 2. Data Preparation  
- Removed HTML tags from question and answer bodies.  
- Created a **content column** combining title + description.  
- Stored the data in a BigQuery table:  


---

### 3. Summarization  
- Some tickets contain long and noisy descriptions → This can mislead embeddings.  
- Used **BigQuery ML’s `ML.GENERATE_TEXT`** function to create concise summaries.  
- **Model Used** → **Gemini Flash 2.0**, created via **BigQuery UI**.  
- System prompt ensures:  
- Focus on **technical details**  
- Generate summaries of **≤5 sentences**  
- Avoid irrelevant information  

---

### 4. Embeddings  
- Generated semantic embeddings using **`ML.GENERATE_EMBEDDING`**.  
- **Model Used** → `text-multilingual-embedding-002` (created via BigQuery UI).  
- Chosen because tickets in real companies may not always be in English.  
- Example: In Japan, tickets may be written in **Japanese**.  
- Goal: Make the system useful for **global companies**, not just English-speaking ones.  

---

### 5. Similarity Search  
- For each new issue:  
1. Generate summary using `ML.GENERATE_TEXT`.  
2. Generate embeddings using `ML.GENERATE_EMBEDDING`.  
3. Run **`VECTOR_SEARCH`** to find **Top-5 similar tickets**.  

---

### 6. Feedback Loop  
- **If helpful** → Developer can reuse existing solution.  
- **If not helpful** → The issue is added as a **new ticket** into the database with generated summary + embeddings.

---

### 7. Vector Indexing (Note)  
- Not used in this prototype because the dataset size is small (~10k).  
- BigQuery documentation suggests vector indexing is effective only when dataset size ≥ **1M records**.  

---

### 8. Why Summarization First?  
- Raw tickets may be:  
- **Too long**  
- **Contain irrelevant details**  
- Summarization helps avoid **biased embeddings** by focusing only on **key technical aspects**.

---

## ⚙️ How to Run Locally  

setup:
  prerequisites:
    - Python 3.9 or later
    - Google Cloud SDK (if working with BigQuery directly)
    - BigQuery project with required permissions
    - Internet connection for installing dependencies
  steps:
    - step: Clone the repository
      commands:
        - git clone https://github.com/pepetikesavasiddhardha/duplicate_ticket_detector_solution_recommender.git
        - cd duplicate_ticket_detector_solution_recommender
    - step: Install uv package manager
      description: >
        uv is used to manage Python environments and dependencies.
      commands:
        - curl -LsSf https://astral.sh/uv/install.sh | sh
    - step: Install project dependencies
      commands:
        - uv sync
    - step: Run the backend server
      description: >
        Start the Flask backend to serve the app.
      commands:
        - python src/backend/app.py
    - step: Open the application in browser
      url: http://127.0.0.1:5000/

notes:
  - Ensure you have enabled the required BigQuery APIs.
  - Make sure the environment has access to Google credentials if running BigQuery queries.
  - The app uses embeddings and summaries, so you must have the BigQuery ML models created beforehand.
  - If running on free-tier GCP credits, keep dataset sizes small to avoid unexpected charges.

success_message: >
  🎉 Setup complete! Open http://127.0.0.1:5000/ in your browser
  and start using the Duplicate Ticket Detection System locally.
