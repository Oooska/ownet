defmodule SocketTest do
  use ExUnit.Case
  require Logger
  alias Ownet.{Socket, Packet}
  import Mox

  setup :verify_on_exit!

  setup_all do
    Mox.defmock(:gen_tcp, for: GenTCPMock)
    :ok
  end

  setup do
    # Common test data
    test_path = "/28.32D7E0080000/temperature"
    bad_path = "/nonexistent/path"
    {:ok, path: test_path, bad_path: bad_path}
  end

  describe "ping" do
    test "ping sends NOP command" do
      :gen_tcp
      |> expect(:send, fn _socket, data ->
          header = Packet.decode_outgoing_packet(data)
          assert header[:type] == 1
          :ok
        end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet()} end)

      assert Socket.ping(:fakesocket) == :ok
    end

    test "ping reads persistence flag on return header" do
      :gen_tcp
      |> expect(:send, fn _socket, _data -> :ok end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(flags: Packet.calculate_flag([:persistence]))} end)

      assert Socket.ping(:fakesocket) == :ok
    end

    test "ping returns network error tuple on error" do
      :gen_tcp
      |> expect(:send, fn _, _ -> {:error, :enetunreach} end)

      assert Socket.ping(:fakesocket) == {:error, :enetunreach}
    end

    test "handles zero-length response" do
      :gen_tcp
      |> expect(:send, fn _socket, _data -> :ok end)
      |> expect(:recv, fn _socket, _num_bytes ->
        {:ok, return_packet(payloadsize: 0)}
      end)

      assert :ok = Socket.ping(:fakesocket)
    end
  end

  describe "present" do
    test "present sends PRESENT command and returns true if path is present" do
      :gen_tcp
      |> expect(:send, fn _socket, data ->
          header = Packet.decode_outgoing_packet(data)
          assert header[:type] == 6
          :ok
        end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet()} end)

      {:ok, present} = Socket.present(:fakesocket, "/")
      assert present
    end

    test "present returns false on ownet error" do
      :gen_tcp
      |> expect(:send, fn _socket, _data -> :ok end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(ret: -1)} end)

      {:ok, present} = Socket.present(:fakesocket, "/")
      assert present == false
    end

    test "present returns network error tuple on error" do
      :gen_tcp
      |> expect(:send, fn _, _ -> {:error, :enetunreach} end)

      assert Socket.present(:fakesocket, "/") == {:error, :enetunreach}
    end

    test "handles binary paths with null bytes", %{path: path} do
      :gen_tcp
      |> expect(:send, fn _socket, data ->
        assert String.ends_with?(data, <<0>>)
        :ok
      end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet()} end)

      assert {:ok, true} = Socket.present(:fakesocket, path)
    end
  end

  describe "dir" do
    test "dir sends DIRALLSLASH command, reads and parses a list of directories" do
      :gen_tcp
      |> expect(:send, fn _socket, data ->
          header = Packet.decode_outgoing_packet(data)
          assert header[:type] == 9
          :ok
        end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: 36, size: 35)} end)
      |> expect(:recv, fn _socket, num_bytes ->
          assert num_bytes == 36
          {:ok, "/43.E6ABD6010000/,/42.C2D154000000/\0"}
        end)

      {:ok, paths} = Socket.dir(:fakesocket, "/")

      assert "/43.E6ABD6010000/" in paths
      assert "/42.C2D154000000/" in paths
    end

    test "dir parses a single returned directory" do
      :gen_tcp
      |> expect(:send, fn _socket, _data -> :ok end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: 18, size: 17)} end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, "/43.E6ABD6010000/\0"} end)

      {:ok, paths} = Socket.dir(:fakesocket, "/")
      assert "/43.E6ABD6010000/" in paths
    end

    test "dir command returns :ownet_error on owfs error" do
      :gen_tcp
      |> expect(:send, fn _socket, _data -> :ok end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(ret: -1)} end)

      {:ownet_error, reason} = Socket.dir(:fakesocket, "/badpath")
      assert reason == 1
    end

    test "handles empty directory list" do
      :gen_tcp
      |> expect(:send, fn _socket, _data -> :ok end)
      |> expect(:recv, fn _socket, _num_bytes ->
        {:ok, return_packet(payloadsize: 1)}
      end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, <<0>>} end)

      assert {:ok, []} = Socket.dir(:fakesocket, "/")
    end
  end

  describe "read" do
    test "read sends a READ command, and returns the read response" do
      :gen_tcp
      |> expect(:send, fn _socket, data ->
          header = Packet.decode_outgoing_packet(data)
          assert header[:type] == 2
          assert header[:payload] == "/28.32D7E0080000/temperature\0"
          :ok
        end)
      |> expect(:recv, fn _socket, _bytes -> {:ok, return_packet(payloadsize: 12, ret: 12, size: 12)} end)
      |> expect(:recv, fn _socket, bytes ->
          assert bytes == 12
          {:ok, "       21.25"}
        end)

      {:ok, value} = Socket.read(:fakesocket, "/28.32D7E0080000/temperature")
      assert value == "       21.25"
    end

    test "read waits for a packet with a payload" do
      :gen_tcp
      |> expect(:send, fn _socket, _data -> :ok end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: -1)} end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: -1)} end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: -1)} end)
      |> expect(:recv, fn _socket, _bytes -> {:ok, return_packet(payloadsize: 12, ret: 12, size: 12)} end)
      |> expect(:recv, fn _socket, _bytes -> {:ok, "       21.25"} end)

      {:ok, value} = Socket.read(:fakesocket, "/28.32D7E0080000/temperature")
      assert value == "       21.25"
    end

    test "read command returns :ownet_error on owfs error" do
      :gen_tcp
      |> expect(:send, fn _socket, _data -> :ok end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(ret: -1)} end)

      {:ownet_error, reason} = Socket.read(:fakesocket, "/badpath")
      assert reason == 1
    end

    test "read command returns network error tuple on error" do
      :gen_tcp
      |> expect(:send, fn _, _ -> {:error, :enetunreach} end)

      assert Socket.present(:fakesocket, "/") == {:error, :enetunreach}
    end

    test "handles binary data properly" do
      binary_data = <<1, 2, 3, 4, 0>>
      :gen_tcp
      |> expect(:send, fn _socket, _data -> :ok end)
      |> expect(:recv, fn _socket, _num_bytes ->
        {:ok, return_packet(payloadsize: byte_size(binary_data))}
      end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, binary_data} end)

      assert {:ok, ^binary_data} = Socket.read(:fakesocket, "/binary/data")
    end

    test "handles large payloads", %{path: path} do
      large_data = String.duplicate("a", 65536)
      :gen_tcp
      |> expect(:send, fn _socket, _data -> :ok end)
      |> expect(:recv, fn _socket, _num_bytes ->
        {:ok, return_packet(payloadsize: byte_size(large_data))}
      end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, large_data} end)

      assert {:ok, ^large_data} = Socket.read(:fakesocket, path)
    end
  end

  describe "write" do
    test "write sends WRITE command to server, and formats the data correctly" do
      :gen_tcp
      |> expect(:send, fn _socket, data ->
        header = Packet.decode_outgoing_packet(data)
        assert header[:type] == 3
        assert header[:payload] == "/42.C2D154000000/PIO.A\01"
          :ok
        end)
      |> expect(:recv, fn _socket, _bytes -> {:ok, return_packet(size: 1)} end)

      assert :ok == Socket.write(:fakesocket, "/42.C2D154000000/PIO.A", "1")
    end

    test "write command returns :ownet_error on owfs error" do
      :gen_tcp
      |> expect(:send, fn _socket, _data -> :ok end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(ret: -1)} end)

      {:ownet_error, reason} = Socket.write(:fakesocket, "/badpath", "1")
      assert reason == 1
    end

    test "write command returns network error tuple on error" do
      :gen_tcp
      |> expect(:send, fn _, _ -> {:error, :enetunreach} end)

      assert Socket.write(:fakesocket, "/badpath", "1") == {:error, :enetunreach}
    end

    test "handles boolean values" do
      :gen_tcp
      |> expect(:send, fn _socket, data ->
        header = Packet.decode_outgoing_packet(data)
        assert String.ends_with?(header[:payload], "1")
        :ok
      end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet()} end)

      assert :ok = Socket.write(:fakesocket, "/switch", true)
    end

    test "handles :on/:off atoms" do
      :gen_tcp
      |> expect(:send, fn _socket, data ->
        header = Packet.decode_outgoing_packet(data)
        assert String.ends_with?(header[:payload], "0")
        :ok
      end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet()} end)

      assert :ok = Socket.write(:fakesocket, "/switch", :off)
    end

    test "validates packet size matches data length" do
      test_value = "test"
      :gen_tcp
      |> expect(:send, fn _socket, data ->
        header = Packet.decode_outgoing_packet(data)
        assert header[:size] == byte_size(test_value)
        :ok
      end)
      |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet()} end)

      assert :ok = Socket.write(:fakesocket, "/test", test_value)
    end
  end

  defp return_packet(opts \\ []) do
    #payloadsize \\ 0, ret \\ 0, flag \\ 0, size \\ 0, offset \\ 0, payload \\ <<>>)
    <<Keyword.get(opts, :version, 0)::32-integer-signed-big,
      Keyword.get(opts, :payloadsize, 0)::32-integer-signed-big,
      Keyword.get(opts, :ret, 0)::32-integer-signed-big,
      Keyword.get(opts, :flags, 0)::32-integer-signed-big,
      Keyword.get(opts, :size, 0)::32-integer-signed-big,
      Keyword.get(opts, :offset, 0)::32-integer-signed-big
    >>
  end
end
