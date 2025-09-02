from google.cloud import bigquery

# =====================================
# Initialize BigQuery Client
# =====================================
# Creates a reusable BigQuery client instance that will be used
# for executing queries, fetching results, and inserting data.
client = bigquery.Client()


# =====================================
# Function: fetch_similar_issues
# =====================================
def fetch_similar_issues(title: str, description: str):
    """
    Fetches the top 5 most similar issues from BigQuery using:
    1. Google Cloud Vertex AI Embeddings
    2. BigQuery VECTOR_SEARCH for similarity matching.

    Args:
        title (str): Title of the user's reported issue.
        description (str): Detailed description of the issue.

    Returns:
        list: A list of dictionaries where each dictionary contains:
              - id: Unique issue identifier.
              - title: Title of the matched issue.
              - clean_question_body: Processed version of the issue description.
              - clean_answer_body: Processed version of the accepted answer.
              - distance: Cosine similarity distance between embeddings.
    """

    # BigQuery query: generate embeddings for the new ticket and find top 5 closest matches
    query = """
    WITH new_ticket_data AS (
        -- Generate embedding for the current issue (title + description)
        SELECT ml_generate_embedding_result
        FROM ML.GENERATE_EMBEDDING(
            MODEL `duplicate_detection.siddu_txt_embed_model`,
            (SELECT @content AS content),
            STRUCT(TRUE AS flatten_json_output)
        )
    )
    -- Perform vector search to find top 5 similar issues
    SELECT
        base.id,
        base.title,
        base.clean_question_body,
        base.clean_answer_body,
        distance
    FROM VECTOR_SEARCH(
        TABLE `siddudev.duplicate_detection.questions_data_embed`,
        "ml_generate_embedding_result",                     -- Column storing embeddings
        (SELECT ml_generate_embedding_result FROM new_ticket_data),
        "ml_generate_embedding_result",                     -- Compare against embeddings
        distance_type=>"COSINE",                            -- Cosine similarity
        top_k=>5                                            -- Fetch top 5 matches
    )
    ORDER BY distance;
    """

    # Use parameterized query → prevents SQL injection & handles special characters safely
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("content", "STRING", f"{title} {description}")
        ]
    )

    # Execute query safely and wait until completion
    query_job = client.query(query, job_config=job_config)

    # Convert query result to a list of dictionaries for easy JSON serialization
    return [dict(row) for row in query_job.result()]


# =====================================
# Function: insert_new_ticket
# =====================================
def insert_new_ticket(title: str, description: str):
    """
    Inserts a new issue into the BigQuery dataset if no relevant results were found.

    Steps involved:
        1. Generate a unique ID for the ticket.
        2. Generate a concise summary of the issue using Vertex AI.
        3. Create embeddings for the summary using ML.GENERATE_EMBEDDING.
        4. Insert the complete record into the BigQuery table.

    Args:
        title (str): Title of the issue reported by the user.
        description (str): Detailed description of the issue.

    Returns:
        str: Status message confirming the insertion.
    """

    query = """
    INSERT INTO `siddudev.duplicate_detection.questions_data_embed`
    (id, title, clean_question_body, accepted_answer_id, clean_answer_body, summary, ml_generate_embedding_result)
    WITH new_ticket AS (
        -- Step 1: Generate a unique ticket ID and prepare raw input
        SELECT
            CAST(ABS(FARM_FINGERPRINT(GENERATE_UUID())) AS INT64) AS id,
            @title AS title,
            @description AS clean_question_body,
            CAST(NULL AS INT64) AS accepted_answer_id,
            CAST(NULL AS STRING) AS clean_answer_body
    ),
    new_ticket_summary AS (
        -- Step 2: Summarize issue using Vertex AI's ML.GENERATE_TEXT
        SELECT
            id,
            title,
            JSON_VALUE(ml_generate_text_result, '$.candidates[0].content.parts[0].text') AS summary
        FROM
            ML.GENERATE_TEXT(
                MODEL `duplicate_detection.question_rephraser`,
                (
                    SELECT
                        id,
                        title,
                        CONCAT(
                            'I would be sharing a paragraph, the first sentence in it is title of issue and the remaining text is description of the Issue. ',
                            'These are the questions posted by users on stackoverflow and they can be related to any topic related to software development. ',
                            'I want you to summarize this entire information into few sentences. At max 5 sentences not more than that. ',
                            'Do not give too much attention to unnecessary details, just focus on technical aspects/details in the issue and produce summary according to it. ',
                            'The paragraph is as follows: ',
                            title,
                            clean_question_body
                        ) AS prompt
                    FROM new_ticket
                )
            )
    ),
    new_ticket_embed AS (
        -- Step 3: Generate embeddings for the summarized issue
        SELECT
            id,
            title,
            ml_generate_embedding_result
        FROM
            ML.GENERATE_EMBEDDING(
                MODEL `duplicate_detection.siddu_txt_embed_model`,
                (
                    SELECT
                        id,
                        title,
                        summary AS content
                    FROM new_ticket_summary
                ),
                STRUCT(TRUE AS flatten_json_output)
            )
    )
    -- Step 4: Insert the enriched ticket (with summary + embeddings) into the dataset
    SELECT
        nt.*,
        nts.summary,
        nte.ml_generate_embedding_result
    FROM
        new_ticket nt
    LEFT JOIN
        new_ticket_summary nts
    USING (id, title)
    LEFT JOIN
        new_ticket_embed nte
    USING (id, title);
    """

    # Use parameterized queries to safely handle quotes in title/description
    job_config = bigquery.QueryJobConfig(
        query_parameters=[
            bigquery.ScalarQueryParameter("title", "STRING", title),
            bigquery.ScalarQueryParameter("description", "STRING", description)
        ]
    )

    # Execute query and wait for completion before returning
    query_job = client.query(query, job_config=job_config)
    query_job.result()  # Ensures the insert completes successfully

    return "New ticket added and embeddings updated."
