// Run with: npx tsx --test lib/installLogIdempotency.test.ts
// Unit-tests the pure row-building/write-path decision extracted from
// app/api/atlas/logs/route.ts. Does NOT exercise a real Supabase upsert or
// the partial unique index migration (20261022010000_install_logs_client_log_id.sql,
// NOT applied to production) — that requires a live database and is marked
// unverified in the audit report, same disclaimer convention as
// webhookClaimLogic.test.ts for the SQL functions it mirrors.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { buildInstallLogRow, decideWritePath } from './installLogIdempotency'

test('no client_log_id (every log type the Mac app sends today): plain insert, row has no client_log_id field at all', () => {
  assert.equal(decideWritePath(undefined), 'plain_insert')
  const row = buildInstallLogRow({
    userId: 'user-1', appName: 'Serum', filename: 'Install_Serum_1.log',
    logType: 'install', redactedContent: 'ok', deviceName: 'Mac', hardwareUuid: 'uuid-1',
  })
  assert.equal('client_log_id' in row, false)
})

test('client_log_id present (future Mac app update, once migration applied): idempotent upsert path', () => {
  assert.equal(decideWritePath('Install_Serum_1.log'), 'idempotent_upsert')
  const row = buildInstallLogRow({
    userId: 'user-1', appName: 'Serum', filename: 'Install_Serum_1.log',
    logType: 'install', redactedContent: 'ok', deviceName: 'Mac', hardwareUuid: 'uuid-1',
    clientLogId: 'Install_Serum_1.log',
  })
  assert.equal(row.client_log_id, 'Install_Serum_1.log')
})

test('user_id always comes from the function input (the verified token server-side), never echoed from an untrusted field', () => {
  const row = buildInstallLogRow({
    userId: 'verified-user-id', appName: undefined, filename: 'f.log',
    logType: 'install', redactedContent: 'c', deviceName: undefined, hardwareUuid: undefined,
  })
  assert.equal(row.user_id, 'verified-user-id')
})

test('repeated delivery of the same event (same client_log_id) always decides the same write path, deterministically', () => {
  const first = decideWritePath('stable-id-1')
  const retry = decideWritePath('stable-id-1')
  assert.equal(first, retry)
  assert.equal(first, 'idempotent_upsert')
})
