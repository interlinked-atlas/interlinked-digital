import { NextRequest, NextResponse } from 'next/server'
import { Pool } from 'pg'

// One-time migration runner — will be deleted after running
export async function POST(req: NextRequest) {
  const secret = req.headers.get('x-migration-secret')
  if (secret !== 'atlas-migrate-2026') {
    return NextResponse.json({ error: 'unauthorized' }, { status: 401 })
  }

  const pool = new Pool({
    connectionString: process.env.POSTGRES_URL_NON_POOLING,
    ssl: { rejectUnauthorized: false },
  })

  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS install_counts (
        user_id              uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
        installs_today       int  NOT NULL DEFAULT 0,
        today_date           date NOT NULL DEFAULT CURRENT_DATE,
        installs_this_month  int  NOT NULL DEFAULT 0,
        period_start         date NOT NULL DEFAULT date_trunc('month', CURRENT_DATE)::date,
        updated_at           timestamptz NOT NULL DEFAULT now()
      );
      ALTER TABLE install_counts ENABLE ROW LEVEL SECURITY;
      DROP POLICY IF EXISTS "service_role_only" ON install_counts;
      CREATE POLICY "service_role_only" ON install_counts USING (false);
    `)

    await pool.query(`
      CREATE OR REPLACE FUNCTION check_and_increment_install(p_user_id uuid, p_plan text)
      RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $fn$
      DECLARE
        v_row           install_counts;
        v_daily_limit   int;
        v_monthly_limit int;
        v_today         date := CURRENT_DATE;
        v_month_start   date := date_trunc('month', CURRENT_DATE)::date;
      BEGIN
        v_daily_limit   := CASE WHEN p_plan IN ('pro','advanced') THEN 999999 ELSE 3 END;
        v_monthly_limit := CASE WHEN p_plan IN ('pro','advanced') THEN 25 ELSE 10 END;
        INSERT INTO install_counts (user_id, today_date, period_start)
        VALUES (p_user_id, v_today, v_month_start) ON CONFLICT (user_id) DO NOTHING;
        SELECT * INTO v_row FROM install_counts WHERE user_id = p_user_id FOR UPDATE;
        IF v_row.today_date < v_today THEN v_row.installs_today := 0; v_row.today_date := v_today; END IF;
        IF v_row.period_start < v_month_start THEN v_row.installs_this_month := 0; v_row.period_start := v_month_start; END IF;
        IF p_plan NOT IN ('pro','advanced') AND v_row.installs_today >= v_daily_limit THEN
          UPDATE install_counts SET today_date=v_row.today_date,period_start=v_row.period_start,installs_today=v_row.installs_today,installs_this_month=v_row.installs_this_month,updated_at=now() WHERE user_id=p_user_id;
          RETURN jsonb_build_object('allowed',false,'reason','daily_limit','daily_used',v_row.installs_today,'daily_limit',v_daily_limit,'monthly_used',v_row.installs_this_month,'monthly_limit',v_monthly_limit,'daily_remaining',0,'monthly_remaining',v_monthly_limit-v_row.installs_this_month);
        END IF;
        IF v_row.installs_this_month >= v_monthly_limit THEN
          UPDATE install_counts SET today_date=v_row.today_date,period_start=v_row.period_start,installs_today=v_row.installs_today,installs_this_month=v_row.installs_this_month,updated_at=now() WHERE user_id=p_user_id;
          RETURN jsonb_build_object('allowed',false,'reason','monthly_limit','daily_used',v_row.installs_today,'daily_limit',v_daily_limit,'monthly_used',v_row.installs_this_month,'monthly_limit',v_monthly_limit,'daily_remaining',v_daily_limit-v_row.installs_today,'monthly_remaining',0);
        END IF;
        v_row.installs_today := v_row.installs_today + 1;
        v_row.installs_this_month := v_row.installs_this_month + 1;
        UPDATE install_counts SET installs_today=v_row.installs_today,today_date=v_row.today_date,installs_this_month=v_row.installs_this_month,period_start=v_row.period_start,updated_at=now() WHERE user_id=p_user_id;
        RETURN jsonb_build_object('allowed',true,'reason',null,'daily_used',v_row.installs_today,'daily_limit',v_daily_limit,'daily_remaining',v_daily_limit-v_row.installs_today,'monthly_used',v_row.installs_this_month,'monthly_limit',v_monthly_limit,'monthly_remaining',v_monthly_limit-v_row.installs_this_month);
      END; $fn$;
    `)

    await pool.end()
    return NextResponse.json({ ok: true, message: 'Migration applied successfully' })
  } catch (err: any) {
    await pool.end().catch(() => {})
    return NextResponse.json({ ok: false, error: err.message }, { status: 500 })
  }
}
