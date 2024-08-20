defmodule SocketTest do
  use ExUnit.Case
  require Logger
  alias Ownet.{Socket, Packet}
  import Mox

  setup :verify_on_exit!

  test "ping sends NOP command" do
    :gen_tcp
    |> expect(:send, fn _socket, data ->
        header = Packet.decode_outgoing_packet(data)
        assert header[:type] == 1
        :ok
      end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet()} end)

    assert Socket.ping(:fakesocket) == {:ok, false}
  end

  test "ping reads persistence flag on return header" do
    :gen_tcp
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(flags: Packet.calculate_flag([:persistence]))} end)

    assert Socket.ping(:fakesocket) == {:ok, true}
  end

  test "ping returns network error tuple on error" do
    :gen_tcp
    |> expect(:send, fn _, _ -> {:error, :enetunreach} end)

    assert Socket.ping(:fakesocket) == {:error, :enetunreach}
  end

  test "present sends PRESENT command and returns true if path is present" do
    :gen_tcp
    |> expect(:send, fn _socket, data ->
        header = Packet.decode_outgoing_packet(data)
        assert header[:type] == 6
        :ok
      end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet()} end)

    {:ok, present, _} = Socket.present(:fakesocket, "/")
    assert present
  end

  test "present returns false on ownet error" do
    :gen_tcp
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(ret: -1)} end)

    {:ok, present, _} = Socket.present(:fakesocket, "/")
    assert present == false
  end

  test "present reads persistence flag on return header" do
    :gen_tcp
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(flags: Packet.calculate_flag([:persistence]))} end)

    {:ok, _, persistence} = Socket.present(:fakesocket, "/")
    assert persistence
  end

  test "present returns network error tuple on error" do
    :gen_tcp
    |> expect(:send, fn _, _ -> {:error, :enetunreach} end)

    assert Socket.present(:fakesocket, "/") == {:error, :enetunreach}
  end

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

    {:ok, paths, _} = Socket.dir(:fakesocket, "/")

    assert "/43.E6ABD6010000/" in paths
    assert "/42.C2D154000000/" in paths
  end

  test "dir parses a single returned directory" do
    :gen_tcp
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: 18, size: 17)} end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, "/43.E6ABD6010000/\0"} end)

    {:ok, paths, _} = Socket.dir(:fakesocket, "/")
    assert "/43.E6ABD6010000/" in paths
  end

  test "dir waits for a packet with a payload" do
    :gen_tcp
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: -1)} end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: -1)} end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: -1)} end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: 18, size: 17)} end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, "/43.E6ABD6010000/\0"} end)

    {:ok, paths, _} = Socket.dir(:fakesocket, "/")
    assert "/43.E6ABD6010000/" in paths
  end

  test "dir reads persistence flag on return header" do
    :gen_tcp
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: 18, size: 17, flags: Packet.calculate_flag([:persistence]))} end)
    |> expect(:recv, fn _socket, _data -> {:ok, "/43.E6ABD6010000/\0"} end)

    {:ok, _, persistence} = Socket.dir(:fakesocket, "/")
    assert persistence
  end

  test "dir command returns :ownet_error on owfs error" do
    :gen_tcp
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(ret: -1)} end)

    {:ownet_error, reason, _persistence} = Socket.dir(:fakesocket, "/badpath")
    assert reason == 1
  end

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

    {:ok, value, _} = Socket.read(:fakesocket, "/28.32D7E0080000/temperature")
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

    {:ok, value, _} = Socket.read(:fakesocket, "/28.32D7E0080000/temperature")
    assert value == "       21.25"
  end

  test "read reads persistence flag on return header" do
    :gen_tcp
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _bytes -> {:ok, return_packet(payloadsize: 12, ret: 12, size: 12, flags: Packet.calculate_flag([:persistence]))} end)
    |> expect(:recv, fn _socket, _data -> {:ok, "       21.25"} end)

    {:ok, _, persistence} = Socket.read(:fakesocket, "/")
    assert persistence
  end

  test "read command returns :ownet_error on owfs error" do
    :gen_tcp
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(ret: -1)} end)

    {:ownet_error, reason, _persistence} = Socket.read(:fakesocket, "/badpath")
    assert reason == 1
  end

  test "read command returns network error tuple on error" do
    :gen_tcp
    |> expect(:send, fn _, _ -> {:error, :enetunreach} end)

    assert Socket.present(:fakesocket, "/") == {:error, :enetunreach}
  end


  test "write sends WRITE command to server, and formats the data correctly" do
    :gen_tcp
    |> expect(:send, fn _socket, data ->
      header = Packet.decode_outgoing_packet(data)
      assert header[:type] == 3
      assert header[:payload] == "/42.C2D154000000/PIO.A\01"
        :ok
      end)
    |> expect(:recv, fn _socket, _bytes -> {:ok, return_packet(size: 1)} end)

    {ok, _} = Socket.write(:fakesocket, "/42.C2D154000000/PIO.A", "1")
    assert ok == :ok
  end

  test "write command returns :ownet_error on owfs error" do
    :gen_tcp
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(ret: -1)} end)

    {:ownet_error, reason, _persistence} = Socket.write(:fakesocket, "/badpath", "1")
    assert reason == 1
  end

  test "write command returns network error tuple on error" do
    :gen_tcp
    |> expect(:send, fn _, _ -> {:error, :enetunreach} end)

    assert Socket.write(:fakesocket, "/badpath", "1") == {:error, :enetunreach}
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
