Just decodes a jwt and shows the info.
Additionally,
- Shows the date/time formats in Human Readable format. 
- Shows the lifespan of the token
- Decode the human readable time format in any timezone 
```sh
./decode-jwt.sh <your_jwt_here> America/Los_Angeles
# OR
./decode-jwt.sh <your_jwt_here> PST
# OR
./decode-jwt.sh <your_jwt_here> PDT
# OR
./decode-jwt.sh <your_jwt_here> UTC-8
```
