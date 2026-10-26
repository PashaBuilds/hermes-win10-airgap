from manim import *

class DemoScene(Scene):
    def construct(self):
        title = Text('Hermes Media Tools', font_size=42)
        self.play(Write(title))
        self.wait(1)
