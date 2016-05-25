open Lwt
open Telegram.Api

module MyBot = Mk (struct
  open Chat
  open Command
  open Message

  include Telegram.BotDefaults

  let token = [%blob "../bot.token"]
  let command_postfix = Some "mlbot" (* Can be replaced with whatever the bot's name is, makes the bot only respond to /say_hi@mlbot *)

  let commands =
    let say_hi = function
      | {chat} -> SendMessage (chat.id, "Hi", false, None, None) in
    let my_pics = function
      | {chat; from = Some {id}} ->
        GetUserProfilePhotos (id, None, None,
                              function
                              | Result.Success photos ->
                                SendMessage (chat.id, "Your photos: " ^ string_of_int photos.total_count, false, None, None)
                              | _ -> SendMessage (chat.id, "Couldn't get your profile pictures!", false, None, None))
      | {chat} -> SendMessage (chat.id, "Couldn't get your profile pictures!", false, None, None) in
    [{name = "say_hi"; description = "Say hi!"; enabled = true; run = say_hi};
     {name = "my_pics"; description = "Count profile pictures"; enabled = true; run = my_pics}]
end)

let () = MyBot.run ()
