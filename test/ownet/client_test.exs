defmodule ClientTest do
  use ExUnit.Case

  alias Ownet.Client
  import Mox

  setup :verify_on_exit!

  setup_all do
    Mox.defmock(:gen_tcp, for: GenTCPMock)
    :ok
  end


  test "commands connect to server when no socket exists" do
    :gen_tcp
    |> expect(:connect, fn _addr, _port, _opts ->
        {:ok, :fakesocket}
      end)
    |> expect(:send, fn _socket, _data ->
        :ok
      end)
    |> expect(:recv, fn _socket, _num_bytes ->
        {:ok, return_packet()}
      end)

    client = Client.new("localhost")
    assert client.socket == nil
    {client2, _} = Client.ping(client)
    assert client2.socket == :fakesocket
  end

  test "socket reconnects to server and retries command when closed" do
    :gen_tcp
    |> expect(:send, fn _socket, _data ->
        {:error, :closed}
      end)
    |> expect(:connect, fn _addr, _port, _opts ->
        {:ok, :reconnectedfakesocket}
      end)
    |> expect(:send, fn _socket, _data ->
        :ok
      end)
    |> expect(:recv, fn _socket, _num_bytes ->
        {:ok, return_packet()}
      end)

    client = client_with_fake_socket()
    {client2, :ok} = Client.ping(client)
    assert client2.socket == :reconnectedfakesocket
  end

  test "commands return an error tuple on other network errors" do
    :gen_tcp
    |> expect(:send, fn _sock, _data ->
      {:error, :enetunreach}
    end)
L
    client = client_with_fake_socket()
    assert {^client, {:error, :enetunreach}} = Client.ping(client)
  end


  test "Client present command returns true when location exists" do
    :gen_tcp
    |> expect(:send, fn _socket, _data ->
        :ok
      end)
    |> expect(:recv, fn _socket, _num_bytes ->
        {:ok, return_packet(payload_size: 0, ret: -1, payload: "")}
      end)



    client = client_with_fake_socket()
    assert {^client, {:ok, false}} = Client.present(client, "/notpresent")
  end

  test "Client present command returns false when location does not exist" do
    :gen_tcp
    |> expect(:send, fn _socket, _data ->
        :ok
      end)
    |> expect(:recv, fn _socket, _num_bytes ->
        {:ok, return_packet(payload_size: 8, payload: "\0\0\0\0\0\0\0\0")}
      end)

    client = client_with_fake_socket()
    assert {^client, {:ok, true}} = Client.present(client, "/")
  end



  test "Client dir command returns a list of sensor directories" do
    {header, data} = return_packet_with_data("/28.32D7E0080000,/42.C2D154000000")
    :gen_tcp
    |> expect(:send, fn _socket, _data ->
        :ok
      end)
    |> expect(:recv, fn _socket, _num_bytes ->
      {:ok, header}
    end)
    |> expect(:recv, fn _socket, _num_bytes ->
      {:ok, data}
    end)

    client = client_with_fake_socket()
    assert {^client, {:ok, ["/28.32D7E0080000", "/42.C2D154000000"]}} = Client.dir(client, "/")
  end

  test "Client dir command looks up error code on bad directory" do
    :gen_tcp
    |> expect(:send, fn _socket, _data ->
        :ok
      end)
    |> expect(:recv, fn _socket, _num_bytes ->
      {:ok, return_packet(ret: -1)}
    end)

    client = client_with_fake_socket()
    assert {^client, {:error, "Startup - command line parameters invalid"}} = Client.dir(client, "/bad")
  end


  test "Client read command looks up error code on bad read" do
    :gen_tcp
    |> expect(:send, fn _socket, _data ->
        :ok
      end)
    |> expect(:recv, fn _socket, _num_bytes ->
      {:ok, return_packet(ret: -1)}
    end)

    client = client_with_fake_socket()
    assert {^client, {:error, "Startup - command line parameters invalid"}} = Client.read(client, "/bad")
  end

  defp client_with_fake_socket do
    client = Client.new("localhost")
    %{client | socket: :fakesocket}
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

  defp return_packet_with_data(data) do
    {return_packet(payloadsize: byte_size(data)+1, size: byte_size(data)), data <> <<0>>}
  end
end
