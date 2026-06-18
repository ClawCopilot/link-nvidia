#!/bin/sh

# 后台运行 sing-box
sing-box run -c config.json &

# 运行 Cloudflare Tunnel
cloudflared tunnel --no-autoupdate run --token eyJhIjoiZDBkM2UzZjUyZWI1MDQzYjRlYjU3ZTEzZTkwNzg0OTEiLCJ0IjoiNjU1YWUyYWItZjA3Yi00YzM2LTgwOGQtMzk3OTJjMTAyYjgwIiwicyI6Ik5EZ3pZek5oT1dVdE1HVXhPUzAwTkRCa0xUbGlaRFV0T0dWbU9XRXpNMkk1WkRKaCJ9
