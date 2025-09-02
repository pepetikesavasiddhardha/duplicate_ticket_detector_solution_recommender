-- create table with questions data
create or replace table siddudev.duplicate_detection.questions_data as 
select id, 
    title, 
    REGEXP_REPLACE(body, r'<[^>]+>', '') AS clean_question_body, 
    accepted_answer_id, CONCAT(title, ' ', REGEXP_REPLACE(body, r'<[^>]+>', ''))  as content 
    from 
    `bigquery-public-data.stackoverflow.posts_questions` limit 10000

-- Get answers data by performing left outer join
CREATE OR REPLACE TABLE `siddudev.duplicate_detection.questions_data` AS
WITH existing_data as (
SELECT * FROM `siddudev.duplicate_detection.questions_data` 
),
answers_data AS (
  select id, REGEXP_REPLACE(body, r'<[^>]+>', '') AS clean_answer_body  FROM `bigquery-public-data.stackoverflow.posts_answers` where id IN (SELECT distinct accepted_answer_id FROM existing_data)
)
SELECT ed.*, ad.clean_answer_body FROM existing_data as ed LEFT JOIN answers_data as ad on ed.accepted_answer_id = ad.id;

-- create embeddings data table
create or replace table `siddudev.duplicate_detection.questions_data_embed` as
SELECT * from
  ML.GENERATE_EMBEDDING(
    MODEL `duplicate_detection.siddu_txt_embed_model`,
    (select id, title,clean_question_body, accepted_answer_id, content from `siddudev.duplicate_detection.questions_data`),
    STRUCT(TRUE AS flatten_json_output)
  );

-- drop the original table
DROP TABLE IF EXISTS `siddudev.duplicate_detection.questions_data`

-- drop the unnecessary columns from table
alter table `siddudev.duplicate_detection.questions_data_embed`
drop column ml_generate_embedding_status -- also drop ml_generate_embedding_statistics column
;

-- Check for the top-5 similar tickets using vector search
WITH new_ticket_data AS (
  SELECT ml_generate_embedding_result
  FROM
    ML.GENERATE_EMBEDDING(
      MODEL `duplicate_detection.siddu_txt_embed_model`,
      (SELECT "In Dart 2, How do I run Pub.build(), can some one explain? In Dart 1.x, I was able to use the Pub.build() command, for example by calling it from a grinder.dart script. However, since moving to Dart 2, this approach no longer seems to work. I’m trying to figure out if there’s an updated way to trigger the same functionality. What’s the correct method to achieve the equivalent of Pub.build() in Dart 2? " AS content),
      STRUCT(TRUE AS flatten_json_output)
    )
)
SELECT
  base.id, base.title, base.clean_question_body,base.clean_answer_body, distance
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

  -- generate summary
  CREATE OR REPLACE TABLE siddudev.duplicate_detection.questions_data_embed2 AS (
SELECT id, title, clean_question_body,accepted_answer_id,clean_answer_body,JSON_VALUE(ml_generate_text_result, '$.candidates[0].content.parts[0].text') AS summary
FROM
  ML.GENERATE_TEXT(
    MODEL `duplicate_detection.question_rephraser`,
    (
      SELECT
      id, title, clean_question_body,accepted_answer_id,clean_answer_body,
        CONCAT(
          'I would be sharing a paragraph, the first sentence in it is title of issue and the remaining text is description of the Issue . These are the questions posted by users on stackoverflow and they can be related to any topic related to software development. I want you to summarize this entire information into few sentences. At max 5 sentences not more than that. Do not give too much attention to unnecessary details, just focus on technical aspects/details in the issue and produce summary according to it. The paragraph is as follows:',
          title, clean_question_body) AS prompt
      FROM `siddudev.duplicate_detection.questions_data_embed`)));