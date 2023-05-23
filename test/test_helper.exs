


Mox.defmock(Ownet.MockSocket, for: Ownet.Socket)
Application.put_env(:Ownet, :socket, Ownet.MockSocket)


ExUnit.start()
