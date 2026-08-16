import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { createDecipheriv } from 'crypto'

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY!
)

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

// Server-side decrypt for website downloads.
// Subscriber authenticates, specifies kit_id and file ('atlaskit' or 'txt').
// Server decrypts and streams the plaintext file — browser downloads the actual usable file.
// DEK and master key are never returned; plaintext is streamed once and not persisted.
export async function GET(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '')
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const kitId = req.nextUrl.searchParams.get('kit_id')
  const file  = req.nextUrl.searchParams.get('file') // 'atlaskit' or 'txt'

  if (!kitId) return NextResponse.json({ error: 'kit_id required' }, { status: 400 })
  if (file !== 'atlaskit' && file !== 'txt') {
    return NextResponse.json({ error: 'file must be "atlaskit" or "txt"' }, { status: 400 })
  }

  // Ownership enforced: row must belong to this user
  const { data: kitRow, error: kitErr } = await supabase
    .from('recovery_kits')
    .select('atlaskit_path, txt_path')
    .eq('id', kitId)
    .eq('user_id', user.id)
    .eq('is_deleted', false)
    .single()

  if (kitErr || !kitRow) {
    return NextResponse.json({ error: 'Recovery Kit not found' }, { status: 404 })
  }

  // Fetch the user's encrypted DEK
  const { data: keyRow, error: keyErr } = await supabase
    .from('recovery_kit_keys')
    .select('encrypted_key, key_nonce')
    .eq('user_id', user.id)
    .single()

  if (keyErr || !keyRow) {
    return NextResponse.json({ error: 'Encryption key not found. Sync from the ATLAS app first.' }, { status: 404 })
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
    return NextResponse.json({ error: 'Could not decrypt key. Contact support.' }, { status: 500 })
  }

  // Fetch the encrypted blob from storage
  const storagePath = file === 'atlaskit' ? kitRow.atlaskit_path : kitRow.txt_path
  const { data: blob, error: blobErr } = await supabase.storage
    .from('atlas-recovery-kits')
    .download(storagePath)

  if (blobErr || !blob) {
    return NextResponse.json({ error: 'Could not retrieve Recovery Kit file' }, { status: 500 })
  }

  const envelopeJson = await blob.text()

  let plaintext: Buffer
  try {
    plaintext = decryptEnvelope(envelopeJson, dekBuffer)
  } catch {
    return NextResponse.json({ error: 'Decryption failed — file may be corrupted' }, { status: 500 })
  }

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
