# Encryption

Liteskill uses AES-256-GCM encryption to protect sensitive data at rest, including LLM provider API keys, provider configurations, and MCP server credentials.

## Overview

Module: `Liteskill.Crypto`

| Property | Value |
|----------|-------|
| Algorithm | AES-256-GCM |
| Key derivation | SHA-256 hash of the configured encryption key |
| IV length | 12 bytes (random per encryption) |
| Tag length | 16 bytes |
| AAD | `"liteskill_encrypted_field"` |
| Storage format | Base64-encoded binary: `IV (12) || Tag (16) || Ciphertext` |

## Encryption Key

The encryption key is configured via the `ENCRYPTION_KEY` environment variable. In development and test, a static key is set in the respective config files.

### Generating a Key

```bash
openssl rand -base64 32
```

This produces a base64-encoded 32-byte random value suitable for the `ENCRYPTION_KEY` variable.

### Key Derivation

The raw key material (from the environment variable) is hashed with SHA-256 to produce a fixed 32-byte key:

```elixir
:crypto.hash(:sha256, key_source)
```

This means the `ENCRYPTION_KEY` value can be any string of sufficient entropy -- it does not need to be exactly 32 bytes.

### Boot-Time Validation

On application startup, `Crypto.validate_key!/0` is called to ensure the encryption key is configured. If missing, the application fails fast with a descriptive error rather than crashing on the first encrypt/decrypt operation.

## Custom Ecto Types

Two custom Ecto types provide transparent encryption and decryption at the schema level.

### `Liteskill.Crypto.EncryptedField`

Encrypts a single string value. Used for fields like API keys.

```elixir
# In a schema
field :api_key, Liteskill.Crypto.EncryptedField
```

Behavior:
- **Cast**: Accepts `nil` or binary strings
- **Dump** (write to DB): Encrypts the plaintext with `Crypto.encrypt/1`, stores as base64 string
- **Load** (read from DB): Decrypts with `Crypto.decrypt/1`, returns plaintext

### `Liteskill.Crypto.EncryptedMap`

Encrypts a map (serialized as JSON). Used for structured configuration data.

```elixir
# In a schema
field :provider_config, Liteskill.Crypto.EncryptedMap, default: %{}
```

Behavior:
- **Cast**: Accepts `nil` (cast to empty map) or maps
- **Dump** (write to DB): JSON-encodes the map, then encrypts. Empty maps are stored as `nil`.
- **Load** (read from DB): Decrypts, then JSON-decodes. `nil` values load as empty map.

## What Is Encrypted

The following database fields are encrypted at rest:

| Table | Field | Type | Contents |
|-------|-------|------|----------|
| `llm_providers` | `api_key` | `EncryptedField` | LLM provider API keys (e.g., Anthropic, OpenAI) |
| `llm_providers` | `provider_config` | `EncryptedMap` | Provider-specific configuration |
| `llm_models` | `model_config` | `EncryptedMap` | Model-specific configuration |
| `mcp_servers` | `api_key` | `EncryptedField` | MCP server API keys |
| `mcp_servers` | `headers` | `EncryptedMap` | MCP server custom HTTP headers |

## How Encryption Works

### Encrypt (on database write)

1. Generate a random 12-byte initialization vector (IV)
2. Encrypt the plaintext using AES-256-GCM with the derived key, IV, and AAD
3. Concatenate: `IV || authentication tag || ciphertext`
4. Base64-encode the result for storage in a text column

```elixir
def encrypt(plaintext) do
  key = encryption_key()
  iv = :crypto.strong_rand_bytes(12)
  {ciphertext, tag} = :crypto.crypto_one_time_aead(
    :aes_256_gcm, key, iv, plaintext, @aad, 16, true
  )
  Base.encode64(iv <> tag <> ciphertext)
end
```

### Decrypt (on database read)

1. Base64-decode the stored value
2. Split into IV (12 bytes), tag (16 bytes), and ciphertext
3. Decrypt using AES-256-GCM with the same key, IV, AAD, and tag
4. Return the plaintext

```elixir
def decrypt(encoded) do
  key = encryption_key()
  {:ok, <<iv::binary-12, tag::binary-16, ciphertext::binary>>} = Base.decode64(encoded)
  :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false)
end
```

## Security Considerations

- Each encryption operation uses a **unique random IV**, so encrypting the same plaintext twice produces different ciphertext
- The **authenticated encryption** (GCM mode) prevents tampering -- any modification to the ciphertext, IV, or tag causes decryption to fail
- The **AAD** (`"liteskill_encrypted_field"`) binds the ciphertext to its intended context, preventing cross-field substitution attacks
- `nil` and empty string values are **not encrypted** -- they pass through as `nil`
- **Key rotation** is not currently supported. Changing the `ENCRYPTION_KEY` will make all previously encrypted data unreadable
