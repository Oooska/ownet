defmodule ClientTest do
  use ExUnit.Case

  alias Ownet.{Socket, Client}
  import Mox

  setup :verify_on_exit!

  setup_all do
    Mox.defmock(Ownet.Socket, for: SocketMock)
    Mox.defmock(:gen_tcp, for: GenTCPMock)
    :ok
  end


  test "Client ping command connects to server when no socket exists" do
    :gen_tcp
    |> expect(:connect, fn _addr, _port, _opts ->
        {:ok, :fakesocket}
      end)

    Socket
    |> expect(:ping, fn _socket, _flags ->
        :ok
      end)

    client = Client.new("localhost")
    assert client.socket == nil
    {client2, :ok} = Client.ping(client)
    assert client2.socket == :fakesocket
  end

  test "Client ping command reconnects to server when socket is closed" do
    :gen_tcp
    |> expect(:connect, fn _addr, _port, _opts ->
        {:ok, :reconnectedfakesocket}
      end)

    Socket
    |> expect(:ping, fn _socket, _flags ->
        {:error, :closed}
      end)
    |> expect(:ping, fn _socket, _flags ->
        :ok
      end)

    client = client_with_fake_socket()
    {client2, :ok} = Client.ping(client)
    assert client2.socket == :reconnectedfakesocket
  end

  test "Client ping command returns error tuple on other network errors" do
    Socket
    |> expect(:ping, fn _socket, _flags ->
        {:error, :enetunreach}
      end)

    client = client_with_fake_socket()
    assert {^client, {:error, :enetunreach}} = Client.ping(client)
  end


  test "Client present command connects to server when no socket exists" do
    :gen_tcp
    |> expect(:connect, fn _addr, _port, _opts ->
        {:ok, :fakesocket}
      end)

    Socket
    |> expect(:present, fn _socket, _path, _flags ->
        {:ok, true}
      end)

    client = Client.new("localhost")
    assert client.socket == nil
    {client2, {:ok, present}} = Client.present(client, "/")
    assert client2.socket == :fakesocket
    assert present
  end

  test "Client present command reconnects to server when socket is closed" do
    :gen_tcp
    |> expect(:connect, fn _addr, _port, _opts ->
        {:ok, :reconnectedfakesocket}
      end)

    Socket
    |> expect(:present, fn _socket, _path, _flags ->
        {:error, :closed}
      end)
    |> expect(:present, fn _socket, _path, _flags ->
        {:ok, true}
      end)

    client = client_with_fake_socket()
    {client2, {:ok, present}} = Client.present(client, "/")
    assert client2.socket == :reconnectedfakesocket
    assert present
  end

  test "Client present command returns error tuple on other network errors" do
    Socket
    |> expect(:present, fn _socket, _path, _flags ->
        {:error, :enetunreach}
      end)

    client = client_with_fake_socket()
    assert {^client, {:error, :enetunreach}} = Client.present(client, "/")
  end

  test "Client present command returns true or false and also reconnects on close" do
    Socket
    |> expect(:present, fn _socket, _path, _flags ->
        {:ok, false}
      end)
    |> expect(:present, fn _socket, _path, _flags ->
        {:error, :closed}
      end)
    |> expect(:present, fn _socket, _path, _flags ->
        {:ok, true}
      end)

    :gen_tcp
    |> expect(:connect, fn _addr, _port, _opts ->
        {:ok, :reconnectedfakesocket}
      end)

    client = client_with_fake_socket()
    assert {^client, {:ok, false}} = Client.present(client, "/")
    assert client.socket == :fakesocket
    assert {client2, {:ok, true}} = Client.present(client, "/")
    assert client2.socket == :reconnectedfakesocket
  end

  test "Client dir command connects to server when no socket exists" do
    :gen_tcp
    |> expect(:connect, fn _addr, _port, _opts ->
        {:ok, :fakesocket}
      end)

    Socket
    |> expect(:dir, fn _socket, _path, _flags ->
        {:ok, ["/28.32D7E0080000", "/42.C2D154000000"]}
      end)

    client = Client.new("localhost")
    assert client.socket == nil
    {client2, {:ok, paths}} = Client.dir(client, "/")
    assert client2.socket == :fakesocket
    assert paths == ["/28.32D7E0080000", "/42.C2D154000000"]
  end

  test "Client dir command reconnects to server when socket is closed" do
    :gen_tcp
    |> expect(:connect, fn _addr, _port, _opts ->
        {:ok, :reconnectedfakesocket}
      end)

    Socket
    |> expect(:dir, fn _socket, _path, _flags ->
        {:error, :closed}
      end)
    |> expect(:dir, fn _socket, _path, _flags ->
        {:ok, ["/28.32D7E0080000", "/42.C2D154000000"]}
      end)

    client = client_with_fake_socket()
    {client2, {:ok, paths}} = Client.dir(client, "/")
    assert client2.socket == :reconnectedfakesocket
    assert paths == ["/28.32D7E0080000", "/42.C2D154000000"]
  end

  test "Client dir command returns error tuple on other network errors" do
    Socket
    |> expect(:dir, fn _socket, _path, _flags ->
        {:error, :enetunreach}
      end)

    client = client_with_fake_socket()
    assert {^client, {:error, :enetunreach}} = Client.dir(client, "/")
  end

  test "Client dir command looks up error code on bad directory" do
    Socket
    |> expect(:dir, fn _socket, _path, _flags ->
      {:ownet_error, 1}
    end)

    client = client_with_fake_socket()
    assert {^client, {:error, "Startup - command line parameters invalid"}} = Client.dir(client, "/bad")
  end

  test "Client read command connects to server when no socket exists" do
    :gen_tcp
    |> expect(:connect, fn _addr, _port, _opts ->
        {:ok, :fakesocket}
      end)

    Socket
    |> expect(:read, fn _socket, _path, _flags ->
        {:ok, "     23.456"}
      end)

    client = Client.new("localhost")
    assert client.socket == nil
    {client2, {:ok, value}} = Client.read(client, "/28.32D7E0080000/temperature")
    assert client2.socket == :fakesocket
    assert value == "     23.456"
  end

  test "Client read command reconnects to server when socket is closed" do
    :gen_tcp
    |> expect(:connect, fn _addr, _port, _opts ->
        {:ok, :reconnectedfakesocket}
      end)

    Socket
    |> expect(:read, fn _socket, _path, _flags ->
        {:error, :closed}
      end)
    |> expect(:read, fn _socket, _path, _flags ->
        {:ok, "value"}
      end)

    client = client_with_fake_socket()
    {client2, {:ok, value}} = Client.read(client, "/")
    assert client2.socket == :reconnectedfakesocket
    assert value == "value"
  end

  test "Client read command returns error tuple on other network errors" do
    Socket
    |> expect(:read, fn _socket, _path, _flags ->
        {:error, :enetunreach}
      end)

    client = client_with_fake_socket()
    assert {^client, {:error, :enetunreach}} = Client.read(client, "/")
  end

  test "Client read command looks up error code on bad read" do
    Socket
    |> expect(:read, fn _socket, _path, _flags ->
      {:ownet_error, 1}
    end)

    client = client_with_fake_socket()
    assert {^client, {:error, "Startup - command line parameters invalid"}} = Client.read(client, "/bad")
  end

  test "Client write command connects to server when no socket exists" do
    :gen_tcp
    |> expect(:connect, fn _addr, _port, _opts ->
        {:ok, :fakesocket}
      end)

    Socket
    |> expect(:write, fn _socket, _path, _value, _flags ->
        :ok
      end)

    client = Client.new("localhost")
    assert client.socket == nil
    {client2, :ok} = Client.write(client, "/42.C2D154000000/PIO.A", "1")
    assert client2.socket == :fakesocket
  end

  test "Client write command reconnects to server when socket is closed" do
    :gen_tcp
    |> expect(:connect, fn _addr, _port, _opts ->
        {:ok, :reconnectedfakesocket}
      end)

    Socket
    |> expect(:write, fn _socket, _path, _value, _flags ->
        {:error, :closed}
      end)
    |> expect(:write, fn _socket, _path, _value, _flags ->
        :ok
      end)

    client = client_with_fake_socket()
    {client2, :ok} = Client.write(client, "/42.C2D154000000/PIO.A", "1")
    assert client2.socket == :reconnectedfakesocket
  end

  test "Client write command returns error tuple on other network errors" do
    Socket
    |> expect(:write, fn _socket, _path, _value, _flags ->
        {:error, :enetunreach}
      end)

    client = client_with_fake_socket()
    assert {^client, {:error, :enetunreach}} = Client.write(client, "/42.C2D154000000/PIO.A", "1")
  end

  test "Client write command looks up error code on bad write" do
    Socket
    |> expect(:write, fn _socket, _path, _value, _flags ->
      {:ownet_error, 1}
    end)

    client = client_with_fake_socket()
    assert {^client, {:error, "Startup - command line parameters invalid"}} = Client.write(client, "/bad", "1")
  end

  defp client_with_fake_socket do
    client = Client.new("localhost")
    %{client | socket: :fakesocket}
  end
end
