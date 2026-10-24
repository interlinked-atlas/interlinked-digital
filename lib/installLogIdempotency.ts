// Pure logic extracted from app/api/atlas/logs/route.ts's write-path decision:
// whether an incoming log write uses the idempotent upsert path (only once
// client_log_id is actually sent — not yet, see the route's own comment) or
// the original plain insert. Mirrors exactly what the route computes so it
// can be unit-tested without a real Supabase call.
export function buildInstallLogRow(input: {
  userId: string
  appName: string | undefined
  filename: string
  logType: string
  redactedContent: string
  deviceName: string | undefined
  hardwareUuid: string | undefined
  clientLogId?: string
}) {
  return {
    user_id: input.userId,
    app_name: input.appName ?? input.filename,
    log_type: input.logType,
    filename: input.filename,
    content: input.redactedContent,
    device_name: input.deviceName ?? 'Unknown device',
    hardware_uuid: input.hardwareUuid ?? '',
    ...(input.clientLogId !== undefined ? { client_log_id: input.clientLogId } : {}),
  }
}

export type WritePath = 'idempotent_upsert' | 'plain_insert'

export function decideWritePath(clientLogId: string | undefined): WritePath {
  return clientLogId !== undefined ? 'idempotent_upsert' : 'plain_insert'
}
