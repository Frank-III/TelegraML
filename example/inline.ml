open Lwt
open Telegram.Api

module MyBot = Mk (struct
  open Command
  open InlineQuery

  include Telegram.BotDefaults

  let token = [%blob "../bot.token"]
  let inline {id; query} =
    print_endline ("Someone said: '" ^ query ^ "'");
    let response = InlineQuery.Out.create_article ~id:"QueryTest" ~title:"Test" ~message_text:query () in
    AnswerInlineQuery (id, [response], None, None, None)
end)

let rec main () =
  let open Lwt in
  let process = function
    | Result.Success _ -> return ()
    | Result.Failure e ->
      if e <> "Could not get head" then (* Ignore "no updates" error *)
        Lwt_io.printl e
      else return () in
  let rec loop () = MyBot.pop_update () >>= process >>= loop in
  (* Sometimes we get exceptions when the connection/SSL gets messed up *)
  try Lwt_main.run (loop ())
  with _ -> main ()

let _ = main ()
