# Supabase Migrations

## Database Connection

Use the **pooler connection** for migrations (not direct connection):

```bash
# Connection string (found in scripts/dump_schema.sh)
PG_DUMP_URL="postgresql://postgres.galytxxkrbksilekmhcw:4ogIUdwWzVyPH0nU@aws-0-ap-northeast-2.pooler.supabase.com:6543/postgres?sslmode=require"
```

## Executing Migrations

### Manual Migration Execution
When Supabase CLI fails or for manual schema updates:

```bash
# Execute a migration file
psql "$PG_DUMP_URL" -f supabase/migrations/YYYYMMDD_HHMMSS_migration_name.sql

# Example:
psql "$PG_DUMP_URL" -f supabase/migrations/20250902_001000_fix_governance_defaults.sql
```

### Check Current Schema
```bash
# Generate current schema snapshot
./scripts/dump_schema.sh

# Check if specific table exists
psql "$PG_DUMP_URL" -c "SELECT table_name FROM information_schema.tables WHERE table_name = 'workspace_governance_settings';"

# Check workspace governance settings
psql "$PG_DUMP_URL" -c "SELECT * FROM workspace_governance_settings LIMIT 5;"
```

### Migration Best Practices

1. **Always test migrations** on local/staging first
2. **Use IF NOT EXISTS** for CREATE statements
3. **Include rollback instructions** in migration comments
4. **Verify RLS policies** are properly configured
5. **Update schema snapshot** after successful migrations

### Common Migration Patterns

```sql
-- Safe table creation
CREATE TABLE IF NOT EXISTS public.new_table (...);

-- Safe column addition  
ALTER TABLE public.existing_table ADD COLUMN IF NOT EXISTS new_column text;

-- Safe function replacement
CREATE OR REPLACE FUNCTION public.function_name(...) RETURNS ... AS $$
-- function body
$$;

-- Safe enum extension
ALTER TYPE public.enum_name ADD VALUE IF NOT EXISTS 'new_value';
```

### Environment Variables

The connection string uses different credentials than your local `.env`:
- **Local dev**: `DATABASE_URL` in `.env` 
- **Migrations**: Pooler URL with different credentials in `scripts/dump_schema.sh`

Always use the **pooler connection** for migrations to avoid connection issues.