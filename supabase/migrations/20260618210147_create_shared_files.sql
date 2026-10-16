
CREATE TABLE IF NOT EXISTS shared_files (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id      UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  file_name    TEXT NOT NULL,
  file_size    BIGINT NOT NULL,
  storage_path TEXT NOT NULL,
  uploaded_at  TIMESTAMPTZ DEFAULT NOW(),
  expires_at   TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '7 days')
);

ALTER TABLE shared_files ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own files"   ON shared_files FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users insert own files" ON shared_files FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users delete own files" ON shared_files FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX idx_shared_files_user ON shared_files(user_id);
CREATE INDEX idx_shared_files_expires ON shared_files(expires_at);
