import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { createDecipheriv } from 'crypto'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

const ADMIN_EMAIL = 'titantinstaller@gmail.com'

function getMasterKey(): Buffer {
  const hex = process.env.RECOVERY_KIT_MASTER_KEY
  if (!hex || hex.length !== 64) throw new Error('RECOVERY_KIT_MASTER_KEY not configured')
  const key = Buffer.from(hex, 'hex')
  if (key.length !== 32) throw new Error('RECOVERY_KIT_MASTER_KEY contains non-hex characters')
  return key
}

function decryptDEK(encrypted: string, nonce: string, masterKey: Buffer): Buffer {
  const combined = Buffer.from(encrypted, 'base64')
  const tag = combined.subarray(combined.length - 16)
  const ciphertext = combined.subarray(0, combined.length - 16)
  const iv = Buffer.from(nonce, 'base64')
  const decipher = createDecipheriv('aes-256-gcm', masterKey, iv)
  decipher.setAuthTag(tag)
  return Buffer.concat([decipher.update(ciphertext), decipher.final()])
}

function decryptEnvelope(envelopeJson: string, dekBuffer: Buffer): Buffer {
  const envelope = JSON.parse(envelopeJson) as { v: number; nonce: string; ciphertext: string }
  const combined = Buffer.from(envelope.ciphertext, 'base64')
  const tag = combined.subarray(combined.length - 16)
  const ciphertext = combined.subarray(0, combined.length - 16)
  const iv = Buffer.from(envelope.nonce, 'base64')
  const decipher = createDecipheriv('aes-256-gcm', dekBuffer, iv)
  decipher.setAuthTag(tag)
  return Buffer.concat([decipher.update(ciphertext), decipher.final()])
}

// Admin-only: server-side decrypt and stream actual kit.atlaskit or kit.txt for a subscriber.
// Admin never receives DEK or master key — only the decrypted file bytes.
// Every download is audit-logged before the file is returned.
export async function GET(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '')
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (user.email?.toLowerCase() !== ADMIN_EMAIL.toLowerCase()) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  }

  const kitId = req.nextUrl.searchParams.get('kit_id')
  const file  = req.nextUrl.searchParams.get('file') // 'atlaskit' or 'txt'

  if (!kitId) return NextResponse.json({ error: 'kit_id required' }, { status: 400 })
  if (file !== 'atlaskit' && file !== 'txt') {
    return NextResponse.json({ error: 'file must be "atlaskit" or "txt"' }, { status: 400 })
  }

  // Fetch kit row — no user_id restriction, admin can access any kit
  const { data: kitRow, error: kitErr } = await supabase
    .from('recovery_kits')
    .select('user_id, atlaskit_path, txt_path')
    .eq('id', kitId)
    .eq('is_deleted', false)
    .single()

  if (kitErr || !kitRow) {
    return NextResponse.json({ error: 'Recovery Kit not found' }, { status: 404 })
  }

  // Fetch subscriber's encrypted DEK
  const { data: keyRow, error: keyErr } = await supabase
    .from('recovery_kit_keys')
    .select('encrypted_key, key_nonce')
    .eq('user_id', kitRow.user_id)
    .single()

  if (keyErr || !keyRow) {
    return NextResponse.json({ error: 'Subscriber encryption key not found' }, { status: 404 })
  }

  let masterKey: Buffer
  try {
    masterKey = getMasterKey()
  } catch {
    return NextResponse.json({ error: 'Server configuration error' }, { status: 500 })
  }

  let dekBuffer: Buffer
  try {
    dekBuffer = decryptDEK(keyRow.encrypted_key, keyRow.key_nonce, masterKey)
  } catch {
    return NextResponse.json({ error: 'Could not decrypt subscriber key' }, { status: 500 })
  }

  const storagePath = file === 'atlaskit' ? kitRow.atlaskit_path : kitRow.txt_path
  const { data: blob, error: blobErr } = await supabase.storage
    .from('atlas-recovery-kits')
    .download(storagePath)

  if (blobErr || !blob) {
    return NextResponse.json({ error: 'Could not retrieve Recovery Kit file from storage' }, { status: 500 })
  }

  const envelopeJson = await blob.text()

  let plaintext: Buffer
  try {
    plaintext = decryptEnvelope(envelopeJson, dekBuffer)
  } catch {
    return NextResponse.json({ error: 'Decryption failed — file may be corrupted' }, { status: 500 })
  }

  // Audit log written after successful decryption, before response
  await supabase.from('recovery_kit_admin_audit').insert({
    admin_user_id:      user.id,
    admin_email:        user.email,
    subscriber_user_id: kitRow.user_id,
    kit_id:             kitId,
    action:             file === 'atlaskit' ? 'download_atlaskit' : 'download_txt',
  })

  const filename = file === 'atlaskit' ? 'kit.atlaskit' : 'kit.txt'
  const contentType = file === 'atlaskit' ? 'application/octet-stream' : 'text/plain; charset=utf-8'

  return new NextResponse(plaintext, {
    status: 200,
    headers: {
      'Content-Type': contentType,
      'Content-Disposition': `attachment; filename="${filename}"`,
      'Content-Length': String(plaintext.length),
      'Cache-Control': 'no-store',
    },
  })
}
