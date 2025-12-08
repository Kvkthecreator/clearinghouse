-- Add columns (nullable; don't break legacy rows)
ALTER TABLE public.baskets
  ADD COLUMN IF NOT EXISTS idempotency_key uuid;

ALTER TABLE public.raw_dumps
  ADD COLUMN IF NOT EXISTS dump_request_id uuid;

-- Partial unique indexes (only enforce when keys present)
CREATE UNIQUE INDEX IF NOT EXISTS uq_baskets_user_idem
  ON public.baskets (user_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_dumps_basket_req
  ON public.raw_dumps (basket_id, dump_request_id)
  WHERE dump_request_id IS NOT NULL;

-- (Optional) shape checks; validate later to avoid locks
ALTER TABLE public.baskets
  ADD CONSTRAINT baskets_idem_is_uuid
  CHECK (idempotency_key IS NULL OR idempotency_key::text ~* '^[0-9a-f-]{36}$') NOT VALID;

ALTER TABLE public.raw_dumps
  ADD CONSTRAINT dumps_req_is_uuid
  CHECK (dump_request_id IS NULL OR dump_request_id::text ~* '^[0-9a-f-]{36}$') NOT VALID;

-- Add comments for documentation
COMMENT ON COLUMN public.baskets.idempotency_key IS 'UUID for basket creation idempotency - ensures unique basket per (user_id, idempotency_key)';
COMMENT ON COLUMN public.raw_dumps.dump_request_id IS 'UUID for dump creation idempotency - ensures unique dump per (basket_id, dump_request_id)';