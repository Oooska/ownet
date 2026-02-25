defmodule IntegerationTest do
  use ExUnit.Case

  # Integration test that should be run against owserver with 4 fake devices
  # owserver --server=localhost --fake=DS2408,DS2408,DS18S20,DS18S20
  # The devcontainer should start the owserver with the above command
  # 4 devices are created, 2 DS2408 (relays) and 2 DS18S20 (temperature sensors)

  # They're addresses are random, but in the form:
  #  ["/29.67C6697351FF/", "/29.4AEC29CDBAAB/", "/10.F2FBE3467CC2/","/10.54F81BE8E78D/"]
  #  The first two are DS2408, the last two are DS18S20

  # Reading values results in random values. Writing values to relays (PIO.#) are accepted, but not stored.

  setup_all do
    {:ok, pid} = Ownet.start_link(name: Ownet)

    {:ok, dirs} = Ownet.dir(pid, "/")
    [ds2408] = Enum.filter(dirs, fn dir -> dir =~ "/29." end) |> Enum.take(1)
    [ds18s20] = Enum.filter(dirs, fn dir -> dir =~ "/10." end) |> Enum.take(1)

    {:ok, %{pid: pid, ds2408: ds2408, ds18s20: ds18s20}}
  end

  describe "dir test" do
    test "dir lists all devices", %{pid: pid} do
      assert {:ok, dirs} = Ownet.dir(pid, "/")

      assert length(dirs) == 4

      ds18s20s = Enum.filter(dirs, fn dir -> dir =~ "/10." end)
      assert length(ds18s20s) == 2

      ds2408s = Enum.filter(dirs, fn dir -> dir =~ "/29." end)
      assert length(ds2408s) == 2
    end

    test "dir on device lists all endpoints", %{pid: pid, ds2408: ds2408} do
      assert {:ok, endpoints} = Ownet.dir(pid, ds2408)
      assert length(endpoints) == 47
      pio_endpoints = Enum.filter(endpoints, fn endpoint -> endpoint =~ "/PIO." end)
      # 8 relays + .ALL + .BYTE
      assert length(pio_endpoints) == 10
    end
  end

  describe "read operations" do
    test "read type as string", %{pid: pid, ds2408: ds2408, ds18s20: ds18s20} do
      assert {:ok, "DS2408"} = Ownet.read(pid, ds2408 <> "type")
      assert {:ok, "DS18S20"} = Ownet.read(pid, ds18s20 <> "type")
    end

    test "read PIO as boolean values", %{pid: pid, ds2408: ds2408} do
      pio_path = ds2408 <> "PIO.0"
      {:ok, val} = Ownet.read_bool(pid, pio_path)
      assert is_boolean(val)
    end

    test "attempting to read value that is not bool returns error", %{pid: pid, ds2408: ds2408} do
      assert {:error, :invalid_type} = Ownet.read_bool(pid, ds2408 <> "address")
    end

    test "read PIO byte as integer", %{pid: pid, ds2408: ds2408} do
      byte_path = ds2408 <> "PIO.BYTE"
      assert {:ok, value} = Ownet.read_int(pid, byte_path)
      assert is_integer(value)
    end

    test "attempting to read a value that is not an integer returns error", %{
      pid: pid,
      ds2408: ds2408
    } do
      assert {:error, :invalid_type} = Ownet.read_int(pid, ds2408 <> "type")
    end

    test "read temperature as float", %{pid: pid, ds18s20: ds18s20} do
      temp_path = ds18s20 <> "temperature"

      assert {:ok, temp} = Ownet.read_float(pid, temp_path)
      assert is_float(temp)

      # Test different temperature scales
      assert {:ok, celsius} = Ownet.read_float(pid, temp_path, flags: [:c])
      assert is_float(celsius)
      assert {:ok, fahrenheit} = Ownet.read_float(pid, temp_path, flags: [:f])
      assert is_float(fahrenheit)
    end

    test "attempting to read a value that is not a float returns error", %{
      pid: pid,
      ds18s20: ds18s20
    } do
      assert {:error, :invalid_type} = Ownet.read_float(pid, ds18s20 <> "type")
    end
  end

  describe "write operations" do
    test "write PIO as boolean", %{pid: pid, ds2408: ds2408} do
      pio_path = ds2408 <> "PIO.0"
      assert :ok = Ownet.write(pid, pio_path, "1")
    end

    test "writing to path that is not writeable returns error", %{pid: pid, ds2408: ds2408} do
      assert {:error, "legacy - Not supported"} = Ownet.write(pid, ds2408 <> "address", "1")
    end
  end

  describe "presence detection" do
    test "device presence", %{pid: pid, ds2408: ds2408, ds18s20: ds18s20} do
      assert {:ok, true} = Ownet.present(pid, ds2408)
      assert {:ok, true} = Ownet.present(pid, ds18s20)
      assert {:ok, false} = Ownet.present(pid, "/29.INVALID/")
    end

    test "ping server", %{pid: pid} do
      assert :ok = Ownet.ping(pid)
    end
  end

  describe "error handling" do
    test "invalid path returns error", %{pid: pid} do
      assert {:error, "Startup - command line parameters invalid"} =
               Ownet.read(pid, "/nonexistent/path")
    end

    test "invalid type conversion", %{pid: pid, ds2408: ds2408} do
      # Try to read a non-boolean value as boolean
      assert {:error, :invalid_type} = Ownet.read_bool(pid, ds2408 <> "address")
    end
  end
end
