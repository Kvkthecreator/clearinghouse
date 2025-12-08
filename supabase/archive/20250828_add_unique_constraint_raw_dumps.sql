-- Add proper unique constraint for raw_dumps ON CONFLICT support
-- The existing unique indexes are not sufficient for ON CONFLICT to work
-- PostgreSQL requires actual unique constraints, not just unique indexes

-- Add unique constraint that ON CONFLICT can reference
ALTER TABLE public.raw_dumps 
ADD CONSTRAINT uq_raw_dumps_basket_dump_req 
UNIQUE (basket_id, dump_request_id);

-- Note: This constraint allows NULL values, which is what we want
-- Only rows with non-NULL dump_request_id will be subject to the uniqueness constraint