## natdm left a review:
*Commented on 2021-09-25T13:26:32Z*
> Here is a review comment<br>
> Here is the second line in the comment..<br>
> And here were some spaces, and the last line.<br>

### lua/pulls/api.lua
```diff
@@ -23,6 +23,10 @@ function M.description_edit(pull_req_no, body)
     return github.update_pull_requests(pull_req_no, {body = body})
 end
 
+function M.description_edit_title(pull_req_no, title)
```

> _*natdm* at 2021-09-25T13:26:01Z_:<br>
> Starting review<br>

> natdm at 2021-09-25T22:48:32Z:<br>
> This is a reply..<br>

> natdm at 2021-09-27T05:33:38Z:<br>
> Another reply. 👎 <br>



### lua/pulls/init.lua
```diff
@@ -140,6 +140,8 @@ local function save_reviews(pull_req_no)
         print("unable to get reviews: " .. reviews.error)
         return
     end
+
```

> _*natdm* at 2021-09-25T13:26:13Z_:<br>
> Another review comment<br>


