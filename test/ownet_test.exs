defmodule OwnetTest do
  use ExUnit.Case
  import Mox

  setup_all do
    Mox.defmock(Ownet.Client, for: ClientMock)
    :ok
  end

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    expect(Ownet.Client, :new, fn _address, _port, _flags ->
      :client_state
    end)

    pid = start_supervised!({Ownet, address: "localhost"})

    {:ok, pid: pid}
  end

  describe "read_int/3" do
    test "parses integers from read responses", %{pid: pid} do
      expect(Ownet.Client, :read, fn :client_state, "/test/int", _flags ->
        {:client_state, {:ok, "   42 "}}
      end)

      assert {:ok, 42} = Ownet.read_int(pid, "/test/int")
    end

    test "returns :invalid_type for non-integer values", %{pid: pid} do
      expect(Ownet.Client, :read, fn :client_state, "/test/int", _flags ->
        {:client_state, {:ok, "not_an_int"}}
      end)

      assert {:error, :invalid_type} = Ownet.read_int(pid, "/test/int")
    end
  end

  describe "read_float/3" do
    test "parses floats from read responses", %{pid: pid} do
      expect(Ownet.Client, :read, fn :client_state, "/test/float", _flags ->
        {:client_state, {:ok, "   21.25"}}
      end)

      assert {:ok, 21.25} = Ownet.read_float(pid, "/test/float")
    end

    test "returns errors unchanged", %{pid: pid} do
      expect(Ownet.Client, :read, fn :client_state, "/test/float", _flags ->
        {:client_state, {:error, :timeout}}
      end)

      assert {:error, :timeout} = Ownet.read_float(pid, "/test/float")
    end
  end

  describe "read_bool/3" do
    test "parses string and binary boolean values", %{pid: pid} do
      expect(Ownet.Client, :read, fn :client_state, "/test/bool", _flags ->
        {:client_state, {:ok, "1"}}
      end)

      assert {:ok, true} = Ownet.read_bool(pid, "/test/bool")
    end

    test "returns :invalid_type for unsupported values", %{pid: pid} do
      expect(Ownet.Client, :read, fn :client_state, "/test/bool", _flags ->
        {:client_state, {:ok, "maybe"}}
      end)

      assert {:error, :invalid_type} = Ownet.read_bool(pid, "/test/bool")
    end
  end
end
