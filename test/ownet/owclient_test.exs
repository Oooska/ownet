defmodule ClientTest do
  use ExUnit.Case
  require Logger
  alias Ownet.Client
  alias Ownet.Packet
  import Mox

  setup :verify_on_exit!



  test "ping sends NOP command" do
    Ownet.MockSocket
    |> expect(:send, fn _socket, data ->
        header = Packet.decode_outgoing_packet_header(data)
        assert header[:type] == 1
        :ok
      end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet()} end)

    assert Client.ping(:fakesocket) == {:ok, false}
  end

  test "ping command reads persistence flag on return header" do
    Ownet.MockSocket
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(flags: Packet.calculate_flag([:persistence]))} end)

    assert Client.ping(:fakesocket) == {:ok, true}
  end

  test "ping command returns network error tuple on error" do
    Ownet.MockSocket
    |> expect(:send, fn _, _ -> {:error, :enetunreach} end)

    assert Client.ping(:fakesocket) == {:error, :enetunreach}
  end

  test "present command sends PRESENT command and returns true if path is present" do
    Ownet.MockSocket
    |> expect(:send, fn _socket, data ->
        header = Packet.decode_outgoing_packet_header(data)
        assert header[:type] == 6
        :ok
      end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet()} end)

    {:ok, present, _} = Client.present(:fakesocket, "/")
    assert present
  end

  test "present command returns false on ownet error" do
    Ownet.MockSocket
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(ret: -1)} end)

    {:ok, present, _} = Client.present(:fakesocket, "/")
    assert present == false
  end

  test "present command reads persistence flag on return header" do
    Ownet.MockSocket
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(flags: Packet.calculate_flag([:persistence]))} end)

    {:ok, _, persistence} = Client.present(:fakesocket, "/")
    assert persistence
  end

  test "present command returns network error tuple on error" do
    Ownet.MockSocket
    |> expect(:send, fn _, _ -> {:error, :enetunreach} end)

    assert Client.present(:fakesocket, "/") == {:error, :enetunreach}
  end

  test "dir command sends DIRALLSLASH command, reads and parses a list of directories" do
    Ownet.MockSocket
    |> expect(:send, fn _socket, data ->
        header = Packet.decode_outgoing_packet_header(data)
        assert header[:type] == 9
        :ok
      end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: 36, size: 35)} end)
    |> expect(:recv, fn _socket, num_bytes ->
        assert num_bytes == 36
        {:ok, "/43.E6ABD6010000/,/42.C2D154000000/\0"}
      end)

    {:ok, paths, _} = Client.dir(:fakesocket, "/")

    assert "/43.E6ABD6010000/" in paths
    assert "/42.C2D154000000/" in paths
  end

  test "dir command parses a single returned directory" do
    Ownet.MockSocket
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: 18, size: 17)} end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, "/43.E6ABD6010000/\0"} end)

    {:ok, paths, _} = Client.dir(:fakesocket, "/")
    assert "/43.E6ABD6010000/" in paths
  end

  test "dir command waits for a packet with a payload" do
    Ownet.MockSocket
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet()} end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet()} end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet()} end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(payloadsize: 18, size: 17)} end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, "/43.E6ABD6010000/\0"} end)

    {:ok, paths, _} = Client.dir(:fakesocket, "/")
    assert "/43.E6ABD6010000/" in paths
  end

  test "dir command returns :ownet_error on owfs error" do
    Ownet.MockSocket
    |> expect(:send, fn _socket, _data -> :ok end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, return_packet(ret: -1)} end)

    {:ownet_error, reason, _persistence} = Client.dir(:fakesocket, "/badpath")
    assert reason == 1
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
