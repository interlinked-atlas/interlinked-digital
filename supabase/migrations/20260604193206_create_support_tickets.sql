
CREATE TABLE IF NOT EXISTS support_tickets (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    email           TEXT,
    issue_type      TEXT NOT NULL DEFAULT 'General',
    message         TEXT NOT NULL,
    attached_log_id UUID,
    attached_log_content TEXT,
    status          TEXT NOT NULL DEFAULT 'open',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_insert_own_tickets"
    ON support_tickets FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "users_view_own_tickets"
    ON support_tickets FOR SELECT
    USING (auth.uid() = user_id);
