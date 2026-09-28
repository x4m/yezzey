-- A failed UPDATE must not overwrite the data committed by its retry.
CREATE EXTENSION yezzey;
SET client_min_messages TO WARNING;

SELECT count(*) AS nseg FROM gp_segment_configuration WHERE role = 'p' AND content >= 0 \gset

-- About 28 kB per segment.  With 8 kB blocks AO sends data to yproxy in
-- 16 kB chunks.
CREATE TABLE aborted_upload (id int, v text) WITH (appendonly=true, blocksize=8192) DISTRIBUTED BY (id);
INSERT INTO aborted_upload SELECT i, 'initial' FROM generate_series(1, 1100 * :nseg) i;
SELECT yezzey_define_offload_policy('public', 'aborted_upload');

-- The external file name contains the WAL write position.  Starting on an
-- empty WAL page, the failed attempt does not move it, so the retry uses the
-- same name.
SELECT count(*) = :nseg AS switched FROM gp_dist_random('gp_id') WHERE pg_switch_xlog() IS NOT NULL;

-- The attempt fails on the last row of segment 1, after its first chunk.
SELECT max(id) AS last_id FROM aborted_upload WHERE gp_segment_id = 1 \gset
BEGIN;
-- Unlike a top-level abort, a subtransaction abort does not wake the WAL writer.
SAVEPOINT attempt;
UPDATE aborted_upload SET v = CASE WHEN id = :last_id THEN (id / 0)::text ELSE 'updated' END;
ROLLBACK TO SAVEPOINT attempt;
UPDATE aborted_upload SET v = 'updated';
COMMIT;
CREATE TABLE committed_rows AS SELECT * FROM aborted_upload DISTRIBUTED BY (id);

-- The QEs of this session finish the failed attempt's upload when they exit.
SELECT current_setting('gp_session_id') AS old_session \gset
\c
-- Reader retry warnings must stay on the segments, otherwise
-- statement_timeout cannot cancel a read that never ends.
SET client_min_messages TO ERROR;
SET statement_timeout = '10s';
CREATE FUNCTION wait_for_session_exit(sess int) RETURNS SETOF int AS $$
BEGIN
  WHILE EXISTS (SELECT 1 FROM pg_stat_activity WHERE sess_id = sess) LOOP
    PERFORM pg_sleep(0.1);
    PERFORM pg_stat_clear_snapshot();
  END LOOP;
END $$ LANGUAGE plpgsql EXECUTE ON ALL SEGMENTS;
SELECT count(*) FROM wait_for_session_exit(:old_session);

-- The table must read as committed.
(SELECT * FROM aborted_upload EXCEPT ALL SELECT * FROM committed_rows)
UNION ALL
(SELECT * FROM committed_rows EXCEPT ALL SELECT * FROM aborted_upload);
RESET statement_timeout;

DROP FUNCTION wait_for_session_exit(int);
DROP TABLE committed_rows;
DROP TABLE aborted_upload;
DROP EXTENSION yezzey;
CHECKPOINT;
