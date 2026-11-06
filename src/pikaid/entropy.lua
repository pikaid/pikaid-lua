--- Default operating-system entropy provider for pikaid.
--
-- Lua's standard library has no cryptographic random number generator:
-- `math.random` is explicitly unsuitable for identifier generation. The
-- portable option available to plain Lua 5.3+ is the operating system's
-- cryptographic device, which this module reads with binary I/O.
--
-- On Linux, macOS, and the BSDs the device is `/dev/urandom`, which is
-- suitable for cryptographic use and never blocks once the kernel pool is
-- initialized. On platforms without that device (notably Windows), this
-- provider fails closed; callers must supply their own CSPRNG through
-- `pikaid.new({ entropy = ... })` after verifying it.
--
-- @module pikaid.entropy

local entropy = {}

--- Number of randomness bytes required by pikaid.
entropy.BYTES = 12

--- Path of the operating-system cryptographic device.
entropy.DEVICE = "/dev/urandom"

--- Read `count` bytes from the operating-system CSPRNG.
--
-- The device is opened for every call and closed immediately. Any failure to
-- open, read, or obtain the full byte count raises an error; there is no
-- fallback to a non-cryptographic source.
--
-- @tparam[opt=12] integer count number of bytes to read
-- @treturn string exactly `count` bytes
function entropy.bytes(count)
  count = count or entropy.BYTES

  local file, open_error = io.open(entropy.DEVICE, "rb")
  if not file then
    error(string.format(
      "cannot open %s for cryptographic randomness: %s",
      entropy.DEVICE,
      tostring(open_error)
    ), 0)
  end

  local data, read_error = file:read(count)
  file:close()

  if not data then
    error(string.format(
      "cannot read %d bytes from %s: %s",
      count,
      entropy.DEVICE,
      tostring(read_error)
    ), 0)
  end

  if #data ~= count then
    error(string.format(
      "short read from %s: expected %d bytes, got %d",
      entropy.DEVICE,
      count,
      #data
    ), 0)
  end

  return data
end

return entropy
