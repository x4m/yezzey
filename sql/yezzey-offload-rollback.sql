-- A statement that fails after yezzey_define_offload_policy() must leave the
-- table as it was on every segment.
CREATE EXTENSION yezzey;
SET client_min_messages TO WARNING;

CREATE TABLE offload_rollback (id int) WITH (appendonly=true) DISTRIBUTED BY (id);
INSERT INTO offload_rollback SELECT generate_series(1, 1000);

DO $$
BEGIN
  PERFORM yezzey_define_offload_policy('public', 'offload_rollback');
  RAISE EXCEPTION 'fail after offload';
END $$;

SELECT count(*) FROM gp_dist_random('pg_class') WHERE oid = 'offload_rollback'::regclass AND reltablespace <> 0;
SELECT count(*) FROM gp_dist_random('yezzey.offload_metadata') WHERE reloid = 'offload_rollback'::regclass;

-- The offload can be retried.
SELECT yezzey_define_offload_policy('public', 'offload_rollback');
SELECT count(*), sum(id) FROM offload_rollback;

DROP TABLE offload_rollback;
DROP EXTENSION yezzey;
CHECKPOINT;
