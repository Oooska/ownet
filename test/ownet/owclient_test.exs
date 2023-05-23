defmodule OWClientTest do
  use ExUnit.Case
  alias Ownet.OWClient
  import Mox

  setup :verify_on_exit!
  #<<version::32, payloadsize::32, type::32, flag::32, size::32, offset::32, payload::binary>>
  test "ping sends PING cmd to server" do
    Ownet.MockSocket
    |> expect(:send, fn _socket, data ->
      <<_version::32, _payloadsize::32, type::32, _rest::binary>> = data
      assert type == 1
      :ok
    end)
    |> expect(:recv, fn _socket, _num_bytes -> {:ok, <<0::32, 0::32, 0::32, 0::32, 0::32, 0::32>>} end)


    results = OWClient.ping(:fakesocket)
    assert results == {:ok, false}
  end

  #test "response with persistence flag set returns true for persistence value" do
  #  Ownet.MockSocket
  #  |> expect(:send, fn _socket, _data -> :ok end)
  #  |> expect(:recv, fn _socket, _num_bytes -> {:ok, <<0, 0, 0, 0x00000004, 0, 0>>, <<>>, false} end)
  #end
end
