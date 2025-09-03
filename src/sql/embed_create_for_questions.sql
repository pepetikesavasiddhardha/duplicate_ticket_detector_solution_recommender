-- ===========================================================
--  STACKOVERFLOW ISSUE SIMILARITY PROJECT
-- ===========================================================
-- This SQL script prepares data, generates summaries,
-- creates embeddings, and sets up a table for performing
-- semantic similarity searches on StackOverflow questions.
-- ===========================================================


-- ===========================================================
-- STEP 1: CREATE INITIAL QUESTIONS DATA TABLE
-- ===========================================================
-- - Pulls data from StackOverflow's public dataset.
-- - Cleans question bodies by removing HTML tags.
-- - Prepares a `content` column combining title + body.
-- ===========================================================
CREATE OR REPLACE TABLE siddudev.duplicate_detection.questions_data AS
SELECT 
    id,
    title,
    REGEXP_REPLACE(body, r'<[^>]+>', '') AS clean_question_body,  -- Remove HTML tags from question body
    accepted_answer_id,
    CONCAT(title, ' ', REGEXP_REPLACE(body, r'<[^>]+>', '')) AS content  -- Combine title + question body
FROM 
    `bigquery-public-data.stackoverflow.posts_questions`
LIMIT 10000;


-- ===========================================================
-- STEP 2: ENRICH QUESTIONS TABLE WITH ACCEPTED ANSWERS
-- ===========================================================
-- - Retrieves accepted answers from StackOverflow dataset.
-- - Performs LEFT JOIN so unanswered questions are retained.
-- ===========================================================
CREATE OR REPLACE TABLE `siddudev.duplicate_detection.questions_data` AS
WITH existing_data AS (
    SELECT * 
    FROM `siddudev.duplicate_detection.questions_data`
),
answers_data AS (
    SELECT 
        id, 
        REGEXP_REPLACE(body, r'<[^>]+>', '') AS clean_answer_body
    FROM 
        `bigquery-public-data.stackoverflow.posts_answers`
    WHERE id IN (SELECT DISTINCT accepted_answer_id FROM existing_data)
)
SELECT 
    ed.*, 
    ad.clean_answer_body
FROM 
    existing_data AS ed
LEFT JOIN 
    answers_data AS ad 
ON 
    ed.accepted_answer_id = ad.id;


-- ===========================================================
-- STEP 3: GENERATE SUMMARIES USING TEXT GENERATION MODEL
-- ===========================================================
-- - Uses Vertex AI's ML.GENERATE_TEXT via BigQuery ML.
-- - Summarizes title + description into max 5 concise sentences.
-- ===========================================================
CREATE OR REPLACE TABLE siddudev.duplicate_detection.questions_data_embed AS
(
    SELECT 
        id,
        title,
        clean_question_body,
        accepted_answer_id,
        clean_answer_body,
        JSON_VALUE(ml_generate_text_result, '$.candidates[0].content.parts[0].text') AS summary
    FROM
        ML.GENERATE_TEXT(
            MODEL `duplicate_detection.question_rephraser`,
            (
                SELECT
                    id,
                    title,
                    clean_question_body,
                    accepted_answer_id,
                    clean_answer_body,
                    CONCAT(
                        'I would be sharing a paragraph, the first sentence in it is title of issue and the remaining text is description of the Issue. ',
                        'These are the questions posted by users on stackoverflow and they can be related to any topic related to software development. ',
                        'I want you to summarize this entire information into few sentences. At max 5 sentences not more than that. ',
                        'Do not give too much attention to unnecessary details, just focus on technical aspects/details in the issue and produce summary according to it. ',
                        'The paragraph is as follows: ',
                        title,
                        clean_question_body
                    ) AS prompt
                FROM `siddudev.duplicate_detection.questions_data`
            )
        )
);


-- ===========================================================
-- STEP 4: CREATE FINAL EMBEDDINGS TABLE
-- ===========================================================
-- - Generates embeddings for summarized content.
-- - Uses multilingual embedding model for semantic search.
-- - Stores embeddings in a dedicated column.
-- ===========================================================
CREATE OR REPLACE TABLE `siddudev.duplicate_detection.questions_data_embed` AS
SELECT 
    id,
    title,
    clean_question_body,
    accepted_answer_id,
    clean_answer_body,
    content AS summary,
    ml_generate_embedding_result
FROM
    ML.GENERATE_EMBEDDING(
        MODEL `duplicate_detection.siddu_txt_embed_model`,
        (
            SELECT 
                id,
                title,
                clean_question_body,
                accepted_answer_id,
                clean_answer_body,
                summary AS content
            FROM `siddudev.duplicate_detection.questions_data`
        ),
        STRUCT(TRUE AS flatten_json_output)
    );


-- ===========================================================
-- STEP 5: CLEAN UP INTERMEDIATE TABLES
-- ===========================================================
-- - Drop the temporary `questions_data` table as it's no longer needed.
-- ===========================================================
DROP TABLE IF EXISTS `siddudev.duplicate_detection.questions_data`;


-- ===========================================================
-- STEP 6: PERFORM VECTOR SEARCH FOR SIMILAR QUESTIONS
-- ===========================================================
-- - Uses ML.GENERATE_EMBEDDING to create embeddings for a new query.
-- - Finds top 5 semantically similar StackOverflow questions.
-- - Uses COSINE similarity for accurate matching.
-- ===========================================================
WITH new_ticket_data AS (
    SELECT ml_generate_embedding_result
    FROM
        ML.GENERATE_EMBEDDING(
            MODEL `duplicate_detection.siddu_txt_embed_model`,
            (
                SELECT 
                    "In Dart 2, How do I run Pub.build(), can someone explain? In Dart 1.x, I was able to use the Pub.build() command, for example by calling it from a grinder.dart script. However, since moving to Dart 2, this approach no longer seems to work. I’m trying to figure out if there’s an updated way to trigger the same functionality. What’s the correct method to achieve the equivalent of Pub.build() in Dart 2?" 
                    AS content
            ),
            STRUCT(TRUE AS flatten_json_output)
        )
)
SELECT
    base.id,
    base.title,
    base.clean_question_body,
    base.clean_answer_body,
    distance
FROM
    VECTOR_SEARCH(
        TABLE `siddudev.duplicate_detection.questions_data_embed`,
        "ml_generate_embedding_result",
        (SELECT ml_generate_embedding_result FROM new_ticket_data),
        "ml_generate_embedding_result",
        distance_type=>"COSINE",
        top_k=>5
    )
ORDER BY distance;