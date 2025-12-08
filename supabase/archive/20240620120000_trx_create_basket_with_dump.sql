-- 0-a  Make the cyclic FKs deferable so they are checked at COMMIT
ALTER TABLE raw_dumps
  ALTER CONSTRAINT raw_dumps_basket_id_fkey
  DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE baskets
  ALTER CONSTRAINT baskets_raw_dump_id_fkey
  DEFERRABLE INITIALLY DEFERRED;

-- 0-b  Transactional helper
CREATE OR REPLACE FUNCTION public.create_basket_with_dump(
    p_name text,
    p_body_md text
) RETURNS TABLE(basket_id uuid) LANGUAGE plpgsql AS $$
DECLARE
    v_basket_id uuid := gen_random_uuid();
    v_dump_id   uuid := gen_random_uuid();
BEGIN
    INSERT INTO baskets (id, name, raw_dump_id)
         VALUES (v_basket_id, COALESCE(p_name, 'Untitled Basket'), v_dump_id);

    INSERT INTO raw_dumps (id, basket_id, body_md)
         VALUES (v_dump_id, v_basket_id, p_body_md);

    RETURN QUERY SELECT v_basket_id;
END;
$$;
