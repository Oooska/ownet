<!--
  SPDX-FileCopyrightText: 2026 Evan Horne
  SPDX-License-Identifier: MIT
-->

<!-- MODULEDOC -->
# Ownet
The `Ownet` module provides a client API to interact with an owserver from the OWFS
(1-Wire file system) family. It provides a set of functions to communicate with
owserver, making it possible to read, write, and check the presence of paths in the
1-Wire network.

It's only been tested against the latest version of owserver - `v3.2p4`.
<!-- MODULEDOC -->
## Installation
The package can be installed by adding `ownet` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ownet, "~> 0.1.0"}
  ]
end
```

## Client API
- `start_link/1`: This function starts the GenServer with the provided options and links it to the current process.
- `ping/1`: This function pings the owserver. It's used to check the connection status.
- `present/2`: This function checks if a path is present in the 1-Wire network.
- `dir/2`: This function returns the list of devices or properties for the given path.
- `read/2`: This function reads the value of a property from a given path.
- `read_float/2`: This function reads the value of a property as a float from a given path.
- `read_bool/2`: This function reads the value of a property as a boolean from a given path.
- `write/3`: This function writes a value to a property at a given path.

## Multiple servers
Multiple processes to communicate with different servers can be specified with the `:name` option.

## Connection
The Ownet protocol was initially designed to be "stateless" and would allow only one
command per connection. By default, the `:persistence` flag is set, which will try
to reuse the socket. If the server indicates persistence is not granted, the socket
is closed and discarded. The client will attempt to seamlessly reconnect when the
next command is issued.

If persistence is granted, but the socket times out, an error will be returned.
Attempting the operation again will create a new socket and the operation may succeed.

## Errors
Ownet reads and stores the error codes from owserver at initialization, allowing the
client to handle error scenarios appropriately. Network socket errors are returned in
the form {:error, :inet.posix()}, and usually indicate the server is not reachable
or the socket timed out.

Errors returned from the owserver directly are in the form {:error, String.t()}. These
indicate that the client is communicating with the owserver, but it did not like the
command. The device is no longer being seen by the bus
({:error, "Startup - command line parameters invalid"}), device communication error
({:error, "Device - Device name bad CRC8"}), or the request was malformed for some
other reason.

## Flags
Flags can be passed during `start_link/1` initialization, in which case those flags
will be sent with every command. Flags can also be specified when sending the
command; these will be applied alongside the default ones. If you specify multiple
conflicting flags (e.g. [:c, :f, :k]), results are unspecified.

- `:persistence` - Reuse the network socket for multiple commands. This is a default option.
- `:uncached` - Skips the owfs cache. Default owfs configuration caches responses for
  ~15 seconds; the flag `:uncached` will force owserver to read the value from the
  sensor. An alternative to using the flag is to prepend "uncached" to a path, e.g.
  `Ownet.read("uncached/42.C2D154000000/temperature")`
- `:c`, `:f`, `:k`, `:r` - Specifies temperature scale. `:c` is default.
- `:mbar`, `:atm`, `:mmhg`, `:inhg`, `:psi`  - Specifies pressure scale. `:mbar` is default.
- `:bus_ret` - Shows "special" or "hidden" directories in `dir/2` command responses,
  such as `/system/`.
- `:fdi`, `:fi`, `:fdidc`, `:fdic`, `:fidc`, `:fic` - Changes the way one wire addresses are displayed. `:fdi` is default.

## Example
```elixir
iex(1)> {:ok, pid} = Ownet.start_link(address: 'localhost')
{:ok, #PID<0.151.0>}
iex(32)> Ownet.dir(pid, "/")
{:ok, ["/42.C2D154000000/", "/43.E6ABD6010000/"]}
iex(3)> Ownet.dir(pid, "/42.C2D154000000/")
{:ok,
["/42.C2D154000000/PIO.BYTE", "/42.C2D154000000/PIO.ALL",
  "/42.C2D154000000/PIO.A", "/42.C2D154000000/PIO.B",
  "/42.C2D154000000/address", "/42.C2D154000000/alias", "/42.C2D154000000/crc8",
  "/42.C2D154000000/family", "/42.C2D154000000/fasttemp", ...]}
iex(4)> Ownet.read(pid, "/42.C2D154000000/temperature")
{:ok, "      22.625"}
iex(5)> Ownet.read_float(pid, "/42.C2D154000000/temperature")
{:ok, 22.625}
iex(6)> Ownet.read_float(pid, "/42.C2D154000000/temperature", flags: [:f])
{:ok, 72.725}
iex(7)> Ownet.read(pid, "/42.C2D154000000/PIO.A")
{:ok, "1"}
iex(8)> Ownet.write(pid, "/42.C2D154000000/PIO.A", false)
:ok
iex(9)> Ownet.read(pid, "/42.C2D154000000/PIO.A")
{:ok, "0"}
iex(10)> Ownet.read_bool(pid, "/42.C2D154000000/PIO.A")
{:ok, false}
iex(11)> Ownet.present(pid, "/42.C2D154000000/")
{:ok, true}
iex(12)> Ownet.present(pid, "/NOTPRESENT/")
{:ok, false}
```

## Reading temperature sensors simultaneously

1-Wire temperature sensors take upwards of 750ms to read for full 12-bit resolution. 

If the temperature sensors are powered (e.g. using data, +3v/+5v, and ground wires), you can signal the sensors to begin their analog-to-digital conversion simultaneously, and then read them quickly without 
having to wait for the ADC conversion. 

Note: Temperature sensors in parasitic mode (e.g. using data and ground wires) can not use this feature. 

```elixir
iex(13)> Ownet.write(pid, "/simultaneous/temperature", true)
:ok

# Wait ~0.75 seconds

iex(14)> Ownet.read(pid, "uncached/42.C2D154000000/latesttemp")
{:ok, "     22.1875"}
```

## Tests

Run `mix test` to run the test suite. 

Run `mix test test/integration.exs` to run an integration test against the owserver instance in the devcontainer.   

Alternatively, if you have owserver installed locally, you can run it with `owserver --server=localhost --fake=DS2408,DS2408,DS18S20,DS18S20` to run owserver with the same options.



