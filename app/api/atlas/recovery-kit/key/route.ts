import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { createCipheriv, createDecipheriv, randomBytes } from 'crypto'

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

function encryptDEK(dek: Buffer, masterKey: Buffer): { encrypted: string; nonce: string } {
  const nonce = randomBytes(12)
  const cipher = createCipheriv('aes-256-gcm', masterKey, nonce)
  const ciphertext = Buffer.concat([cipher.update(dek), cipher.final()])
  const tag = cipher.getAuthTag()
  return {
    encrypted: Buffer.concat([ciphertext, tag]).toString('base64'),
    nonce: nonce.toString('base64'),
  }
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

export async function POST(req: NextRequest) {
  const token = req.headers.get('authorization')?.replace('Bearer ', '')
  if (!token) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: { user }, error: authErr } = await supabase.auth.getUser(token)
  if (authErr || !user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const { data: profile } = await supabase
    .from('profiles')
    .select('plan')
    .eq('id', user.id)
    .single()
  if (profile?.plan !== 'pro') {
    return NextResponse.json({ error: 'Cloud Recovery Kit requires ATLAS Pro' }, { status: 403 })
  }

  let masterKey: Buffer
  try {
    masterKey = getMasterKey()
  } catch {
    return NextResponse.json({ error: 'Server configuration error' }, { status: 500 })
  }

  // Return existing DEK if one exists for this user
  const { data: existing } = await supabase
    .from('recovery_kit_keys')
    .select('encrypted_key, key_nonce')
    .eq('user_id', user.id)
    .single()

  if (existing?.encrypted_key && existing?.key_nonce) {
    try {
      const dek = decryptDEK(existing.encrypted_key, existing.key_nonce, masterKey)
      return NextResponse.json({ key: dek.toString('base64') })
    } catch {
      // DEK decryption failed — master key mismatch or corrupt row.
      // Do NOT silently generate a new DEK: that would permanently strand the user's existing cloud kit.
      return NextResponse.json({ error: 'Encryption key could not be retrieved. Contact support.' }, { status: 500 })
    }
  }

  // Generate a fresh 256-bit DEK for this user
  const dek = randomBytes(32)
  const { encrypted, nonce } = encryptDEK(dek, masterKey)

  const { error: upsertErr } = await supabase.from('recovery_kit_keys').upsert(
    { user_id: user.id, encrypted_key: encrypted, key_nonce: nonce, updated_at: new Date().toISOString() },
    { onConflict: 'user_id' }
  )
  if (upsertErr) {
    return NextResponse.json({ error: 'Could not store encryption key' }, { status: 500 })
  }

  return NextResponse.json({ key: dek.toString('base64') })
}
