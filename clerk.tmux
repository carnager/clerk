# Status bar
set-option -g status-position top
set -g status-interval 30
set -g status-justify centre
set -g status-left-length 40
set -g status-left ''
set -g status-right ''


# Colors
set -g status-bg colour235
set -g status-fg default
setw -g window-status-current-bg default
setw -g window-status-current-fg default
setw -g window-status-current-attr dim
setw -g window-status-bg default
setw -g window-status-fg white
setw -g window-status-attr bright
setw -g window-status-format ' #[fg=colour243,bold]#W '
setw -g window-status-current-format ' #[fg=yellow,bold]#[bg=colour235]#W '

# !Dont remove this keybinding header! (used to generate help)
## Key Bindings
bind-key -n F1 findw albums
bind-key -n F2 findw tracks
bind-key -n F3 findw latest
bind-key -n F4 findw playlists
bind-key -n F5 findw queue
bind-key -n C-F5 run-shell 'mpc prev --quiet'
bind-key -n C-F6 run-shell 'mpc toggle --quiet'
bind-key -n C-F7 run-shell 'mpc stop > /dev/null'
bind-key -n C-F8 run-shell 'mpc next --quiet'
bind-key -n F10 run-shell 'clerk -f -x'
bind-key -n C-F1 run-shell 'clerk -f -y'
bind-key -n C-q kill-session -t music


# tmux options
set -g set-titles on
set -g set-titles-string '#T'
set -g default-terminal "screen-256color"
setw -g mode-keys vi
set -sg escape-time 1
set -g repeat-time 1000
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
unbind C-b
set -g prefix C-a
unbind C-p
bind C-p paste-buffer
